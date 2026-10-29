/* Two test-facing forwarders (item XP-G27, rulings HX-C, HX-F). The run-time shader compiler loader
   moved to the portable C target CShaderCross, shared with MetalUIShaderRuntime; these keep the RC
   tests' spelling. Compiled with and without the `SDL` trait. */
#include "SDLBridge.h"
#include "CShaderCross.h"

int32_t mui_sc_loads(void) { return mui_rsc_loads(); }
void mui_sc_test_empty_diagnostics(bool empty) { mui_rsc_test_empty_diagnostics(empty); }
