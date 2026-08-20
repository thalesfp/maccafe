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
use crate::state::{self, AssertionKind};

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
pub struct OnRequest {
    /// How long to stay awake, for example 45s, 90m, 2h, or 1h30m. Omit to stay awake until turned off.
    pub duration: Option<String>,

    /// Let the display sleep, and only keep the system awake.
    pub system_only: Option<bool>,
}

#[derive(Clone)]
pub struct Maccafe {
    #[allow(dead_code)]
    tool_router: ToolRouter<Maccafe>,
}

fn failed(error: anyhow::Error) -> McpError {
    McpError::internal_error(format!("{error:#}"), None)
}

/// The same wire shape the `--json` flag prints, so both transports agree.
fn wire(value: serde_json::Value) -> Result<CallToolResult, McpError> {
    Ok(CallToolResult::success(vec![ContentBlock::text(
        value.to_string(),
    )]))
}

#[tool_router]
impl Maccafe {
    pub fn new() -> Self {
        Self {
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

        let kind = if request.system_only.unwrap_or(false) {
            AssertionKind::System
        } else {
            AssertionKind::Display
        };

        let paths = state::paths().map_err(failed)?;
        let status = control::turn_on(&paths, kind, limit).map_err(failed)?;

        wire(report::status_value(&status))
    }

    #[tool(description = "Let this Mac sleep normally again.")]
    fn caffeine_off(&self) -> Result<CallToolResult, McpError> {
        let paths = state::paths().map_err(failed)?;
        let action = control::turn_off(&paths).map_err(failed)?;

        wire(report::off_value(&action))
    }

    #[tool(description = "Report whether this Mac is being kept awake, and for how much longer.")]
    fn caffeine_status(&self) -> Result<CallToolResult, McpError> {
        let paths = state::paths().map_err(failed)?;
        let status = control::read_status(&paths).map_err(failed)?;

        wire(report::status_value(&status))
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

pub fn serve() -> Result<()> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    runtime.block_on(async {
        let service = Maccafe::new().serve(stdio()).await?;
        service.waiting().await?;

        Ok(())
    })
}
