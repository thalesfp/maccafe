use anyhow::Result;
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{CallToolResult, ContentBlock, Implementation, ServerCapabilities, ServerInfo};
use rmcp::transport::stdio;
use rmcp::{
    ErrorData as McpError, ServerHandler, ServiceExt, schemars, tool, tool_handler, tool_router,
};

use crate::control;
use crate::duration;
use crate::report;
use crate::state::{AssertionKind, Paths};

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
struct OnRequest {
    /// How long to stay awake, for example 45s, 90m, 2h, or 1h30m. Omit to stay awake until turned off.
    #[serde(default)]
    duration: Option<String>,

    /// Let the display sleep, and only keep the system awake.
    #[serde(default)]
    system_only: bool,
}

#[derive(Clone)]
struct Maccafe {
    paths: Paths,
    #[allow(dead_code)]
    tool_router: ToolRouter<Maccafe>,
}

fn failed(error: anyhow::Error) -> McpError {
    McpError::internal_error(format!("{error:#}"), None)
}

fn wire(report: String) -> Result<CallToolResult, McpError> {
    Ok(CallToolResult::success(vec![ContentBlock::text(report)]))
}

#[tool_router]
impl Maccafe {
    fn new(paths: Paths) -> Self {
        Self {
            paths,
            tool_router: Self::tool_router(),
        }
    }

    #[tool(
        description = "Keep this Mac awake. The hold runs in its own process, so it outlives this session and lasts until caffeine_off or the duration runs out."
    )]
    fn caffeine_on(
        &self,
        Parameters(request): Parameters<OnRequest>,
    ) -> Result<CallToolResult, McpError> {
        let limit = request
            .duration
            .as_deref()
            .map(duration::parse)
            .transpose()
            .map_err(|error| McpError::invalid_params(error.to_string(), None))?;

        let kind = AssertionKind::for_system_only(request.system_only);
        let status = control::turn_on(&self.paths, kind, limit).map_err(failed)?;

        wire(report::status(true, &status))
    }

    #[tool(description = "Let this Mac sleep normally again.")]
    fn caffeine_off(&self) -> Result<CallToolResult, McpError> {
        let action = control::turn_off(&self.paths).map_err(failed)?;

        wire(report::off(true, &action))
    }

    #[tool(description = "Report whether this Mac is being kept awake, and for how much longer.")]
    fn caffeine_status(&self) -> Result<CallToolResult, McpError> {
        let status = control::read_status(&self.paths).map_err(failed)?;

        wire(report::status(true, &status))
    }
}

#[tool_handler]
impl ServerHandler for Maccafe {
    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new("maccafe", env!("CARGO_PKG_VERSION")))
            .with_instructions(
                "Keeps a Mac awake with an IOKit power assertion. The hold runs in a separate process, so it survives this session ending. Timestamps are RFC 3339 in UTC."
                    .to_string(),
            )
    }
}

/// The tools are synchronous and never overlap, so a single thread serves them;
/// the timer driver stays on because rmcp uses it to shut the session down.
pub fn serve(paths: &Paths) -> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()?;

    runtime.block_on(async {
        let service = Maccafe::new(paths.clone()).serve(stdio()).await?;
        service.waiting().await?;

        Ok(())
    })
}
