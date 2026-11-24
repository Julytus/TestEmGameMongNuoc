class_name StateMachine
extends Node
## Finite State Machine dạng node: mỗi State là một node con.
## Thêm hành vi mới = thêm node State mới, không phải sửa if/else khổng lồ.

signal state_changed(from: StringName, to: StringName)

@export var initial_state: State

var current_state: State
var _states: Dictionary[StringName, State] = {}


func _ready() -> void:
	for child in get_children():
		var state := child as State
		if state:
			_states[state.name] = state
			state.state_machine = self
	if owner and not owner.is_node_ready():
		await owner.ready
	current_state = initial_state if initial_state else _states.values().front()
	current_state.enter({})


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	var next: State = _states.get(state_name)
	if next == null:
		push_error("%s: không có state '%s'" % [owner.name, state_name])
		return
	var previous := current_state
	if previous:
		previous.exit()
	current_state = next
	current_state.enter(msg)
	state_changed.emit(previous.name if previous else &"", next.name)


func is_in(state_name: StringName) -> bool:
	return current_state != null and current_state.name == state_name
