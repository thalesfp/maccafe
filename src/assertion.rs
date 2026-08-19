use anyhow::{Result, bail};
use core_foundation::base::TCFType;
use core_foundation::string::{CFString, CFStringRef};

use crate::state::AssertionKind;

type IOReturn = i32;
type IOPMAssertionID = u32;
type IOPMAssertionLevel = u32;

const ASSERTION_LEVEL_ON: IOPMAssertionLevel = 255;
const RETURN_SUCCESS: IOReturn = 0;

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    fn IOPMAssertionCreateWithName(
        assertion_type: CFStringRef,
        assertion_level: IOPMAssertionLevel,
        assertion_name: CFStringRef,
        assertion_id: *mut IOPMAssertionID,
    ) -> IOReturn;

    fn IOPMAssertionRelease(assertion_id: IOPMAssertionID) -> IOReturn;
}

fn type_name(kind: AssertionKind) -> &'static str {
    match kind {
        AssertionKind::Display => "PreventUserIdleDisplaySleep",
        AssertionKind::System => "PreventUserIdleSystemSleep",
    }
}

pub struct Assertion {
    id: IOPMAssertionID,
}

impl Assertion {
    pub fn create(kind: AssertionKind) -> Result<Self> {
        let assertion_type = CFString::new(type_name(kind));
        let assertion_name = CFString::new("maccafe");
        let mut id: IOPMAssertionID = 0;

        let result = unsafe {
            IOPMAssertionCreateWithName(
                assertion_type.as_concrete_TypeRef(),
                ASSERTION_LEVEL_ON,
                assertion_name.as_concrete_TypeRef(),
                &mut id,
            )
        };

        if result != RETURN_SUCCESS {
            bail!("IOKit refused the power assertion (IOReturn {result:#x})");
        }

        Ok(Self { id })
    }
}

impl Drop for Assertion {
    fn drop(&mut self) {
        unsafe { IOPMAssertionRelease(self.id) };
    }
}
