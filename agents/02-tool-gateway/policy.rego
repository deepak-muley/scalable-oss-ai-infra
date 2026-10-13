package agents.authz

import rego.v1

# Decision for one tool call. The gateway sends counts. The kill switch
# lives in OPA data (PUT /v1/data/agents/control), which the caller cannot
# set by stuffing a field into the request.
#
# allow_tools is the skill's allow-list. A controller rendering an
# AgentBlueprint would generate this set from spec.policy.allowTools.

allow_tools := {"list_pods", "query_prometheus", "search_docs"}

max_steps := object.get(input, "max_steps", 8)
max_repeats := object.get(input, "max_repeats", 3)

decision := {"allow": false, "reason": "kill switch is on"} if {
	data.agents.control.kill_switch == true
} else := {"allow": false, "reason": "step budget exhausted"} if {
	input.tool_calls > max_steps
} else := {"allow": false, "reason": "same tool repeated; circuit open"} if {
	input.repeated_tool > max_repeats
} else := {"allow": false, "reason": "exec_code requires approval=granted"} if {
	input.tool == "exec_code"
	object.get(input, "approval", "") != "granted"
} else := {"allow": false, "reason": "exec_code requires the gvisor sandbox"} if {
	input.tool == "exec_code"
	object.get(input, "sandbox", "") != "gvisor"
} else := {"allow": true, "reason": "exec_code approved inside the gvisor sandbox"} if {
	input.tool == "exec_code"
} else := {"allow": true, "reason": "read tool on the skill allow-list"} if {
	input.tool in allow_tools
} else := {"allow": false, "reason": "tool is not on the skill allow-list"}
