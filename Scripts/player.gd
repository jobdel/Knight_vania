extends CharacterBody2D

# ═══════════════════════════════════════════
#  STATE MACHINES
# ═══════════════════════════════════════════

## Main player state — movement & actions
enum State {
	IDLE, RUN, JUMP, FALL, WALL_SLIDE,
	LEDGE_GRAB, LEDGE_CLIMB,
	CROUCH, CROUCH_WALK,
	ATTACK, DASH, PARRY,
	HURT, DEAD
}

## Grapple hook sub-state — runs independently
enum GrappleState {
	NONE,        # Ready to fire
	THROW,       # Brief throw freeze (needle flying)
	PULL,        # Pulling player toward anchor
	PULL_ENEMY,  # Pulling enemy toward player
	COOLDOWN     # Post-use cooldown
}

var state : State = State.IDLE
var prev_state : State = State.IDLE
var grapple_state : GrappleState = GrappleState.NONE


# ═══════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════

# Movement
const SPEED := 150.0
const CROUCH_SPEED := 80.0
const JUMP_VELOCITY := -300.0
const WALL_JUMP_FORCE := Vector2(220, -300)
const KNOCKBACK_FORCE := Vector2(120, -100)
const I_FRAMES := 0.8
const HURT_STUN := 0.25

# Dash (Hyper Light Drifter style)
const DASH_MOVE_SPEED := 380.0
const DASH_DURATION := 0.16
const DASH_GHOST_INTERVAL := 0.018
const DASH_GHOST_FADE_TIME := 0.35
const DASH_GHOST_COLOR := Color(0.4, 0.85, 1.0, 0.6)

# Movement feel
const GROUND_ACCEL := 1200.0
const GROUND_DECEL := 1600.0
const AIR_ACCEL := 800.0
const AIR_DECEL := 400.0

# Ledge grab
const LEDGE_GRAB_UP_OFFSET := -6.0
const LEDGE_GRAB_SIDE_OFFSET := 6.0
const LEDGE_JUMP_FORCE := Vector2(0, -300)
const LEDGE_CLIMB_DURATION := 0.35

# Coyote time & jump buffering
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const VARIABLE_JUMP_DAMPEN := 0.45
const MAX_AIR_JUMPS := 1
const DOUBLE_JUMP_VELOCITY := -270.0

# Hit stop / Screen shake
const HITSTOP_ATTACK := 0.04
const HITSTOP_HURT := 0.06
const SHAKE_HURT_STRENGTH := 3.0
const SHAKE_HURT_DURATION := 0.15
const SHAKE_ATTACK_STRENGTH := 1.5
const SHAKE_ATTACK_DURATION := 0.06

# Grapple — Swing-style (directional aiming, pendulum physics)
const GRAPPLE_RANGE := 140.0
const GRAPPLE_ROPE_SEGMENTS := 10
const GRAPPLE_COOLDOWN := 0.5
const GRAPPLE_ARRIVE_DIST := 16.0
const GRAPPLE_MAX_SWING_TIME := 4.0
const GRAPPLE_LAUNCH_SPEED := 340.0
const GRAPPLE_LAUNCH_UP_BIAS := -140.0
const GRAPPLE_ENEMY_PULL_SPEED := 550.0
const GRAPPLE_HOOK_SPEED := 700.0
const GRAPPLE_HOOK_GRAVITY := 500.0
const GRAPPLE_HOOK_MAX_TIME := 0.6
const GRAPPLE_SWING_PUMP := 600.0
const GRAPPLE_ROPE_LENGTHEN_SPEED := 120.0
const GRAPPLE_ROPE_SHORTEN_SPEED := 150.0
const GRAPPLE_ROPE_MIN_LEN := 24.0
const GRAPPLE_RELEASE_BOOST := 1.2          # Slingshot multiplier on well-timed release
const GRAPPLE_SWING_GRAVITY_MULT := 1.3     # Extra gravity during swing for snappy arcs

# Grenade
const GRENADE_THROW_SPEED := 350.0
const GRENADE_THROW_ANGLE := -50.0
const GRENADE_COOLDOWN := 1.5

# Stamina
const MAX_STAMINA := 300.0
const STAMINA_REGEN_RATE := 70.0
const STAMINA_REGEN_DELAY := 0.6
const STAMINA_COST_ATTACK := 20.0
const STAMINA_COST_ATTACK2 := 20.0
const STAMINA_COST_COMBO := 25.0
const STAMINA_COST_CROUCH_ATK := 15.0
const STAMINA_COST_DASH := 25.0
const STAMINA_COST_GRAPPLE := 30.0
const STAMINA_COST_GRENADE := 20.0
const STAMINA_COST_BLAST := 35.0

# Blast
const BLAST_DAMAGE := 2
const BLAST_RADIUS := 50.0
const BLAST_COOLDOWN := 2.0

# Parry
const PARRY_WINDOW := 0.3
const PARRY_DAMAGE := 2
const PARRY_TOTAL_TIME := 0.5

# Combo
const COMBO_WINDOW := 0.35

# Look up/down (Hollow Knight-style camera pan)
const LOOK_PAN_DISTANCE := 60.0
const LOOK_PAN_DELAY := 0.6
const LOOK_PAN_SPEED := 120.0

var gravity : int = ProjectSettings.get_setting("physics/2d/default_gravity")


# ═══════════════════════════════════════════
#  STATE VARIABLES
# ═══════════════════════════════════════════

# Combo
var combo_step := 0
var combo_timer := 0.0

# Dash / Roll

# Dash (HLD-style)
var dash_move_timer := 0.0
var dash_move_dir := 1
var dash_ghost_timer := 0.0

# Facing direction (gameplay truth: 1 = right, -1 = left)
var facing_dir := 1

# Health
var max_health := 10
var health := max_health
var attack_damage := 1

# Stamina
var stamina := MAX_STAMINA
var stamina_regen_cooldown := 0.0

# Invincibility
var is_invincible := false
var invincibility_timer := 0.0
var hurt_timer := 0.0

# Coyote / buffer
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var was_on_floor := false
var air_jumps_left := MAX_AIR_JUMPS

# Hit stop / Screen shake
var hitstop_timer := 0.0
var shake_timer := 0.0
var shake_strength := 0.0

# Attack hit tracking
var attack_hit_bodies : Array = []

# Grapple vars
var grapple_point := Vector2.ZERO
var grapple_aim_dir := Vector2.ZERO
var grapple_line: Line2D
var grapple_hook_tip: Polygon2D
var grapple_hooked_enemy: CharacterBody2D = null
var grapple_cooldown_timer := 0.0
var grapple_swing_timer := 0.0
var grapple_rope_length := 0.0
var grapple_has_reset_air := false
var grapple_hook_pos := Vector2.ZERO
var grapple_hook_vel := Vector2.ZERO
var grapple_hook_flying := true
var grapple_hook_flight_timer := 0.0
var grapple_whiffing := false
var grapple_whiff_timer := 0.0

# Ledge grab
var ledge_ray_upper: RayCast2D
var ledge_ray_lower: RayCast2D
var ledge_climb_timer := 0.0
var ledge_climb_target := Vector2.ZERO
var ledge_grab_wall_dir := 1

# Grenade
var grenade_cooldown_timer := 0.0

# Blast
var blast_cooldown_timer := 0.0
var blast_knockback := false

# Parry
var parry_timer := 0.0
var parry_window_active := false
var parry_succeeded := false

# Stamina UI flash
var stamina_flash_timer := 0.0

# Look up/down
var look_hold_timer := 0.0
var look_pan_offset := 0.0
var look_direction := 0  # -1 = up, 0 = none, 1 = down
var turn_pending_dir := 0  # Non-zero while TurnAround animation is playing
var double_jump_rolling := false  # True while double-jump Roll animation is playing

# Camera baseline offset
const CAMERA_BASE_OFFSET := Vector2(0.0, -40.0)


# ═══════════════════════════════════════════
#  NODES
# ═══════════════════════════════════════════

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var canvas: CanvasLayer = $CanvasLayer
@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
var attack_hitbox: Area2D
@onready var hitbox_shape: CollisionShape2D = $CollisionShapeAttack
@onready var crouch_hitbox_shape: CollisionShape2D = $CollisionShapeCrouchAttack
@onready var body_shape: CollisionShape2D = $CollisionShapePlayer
var _hitbox_base_x: float
var _body_base_x: float

# HUD nodes — health
var health_bar_fill: TextureRect
var health_bar_ghost: TextureRect
var health_bar_frame: TextureRect
var weapon_icon: TextureRect

# HUD nodes — stamina (rounded panels)
var stam_outline: Panel
var stam_bg: Panel
var stam_ghost: Panel
var stam_fill: Panel

# Ghost bar animation
var health_ghost_ratio := 1.0
var health_ghost_delay := 0.0
var stamina_ghost_ratio := 1.0
var stamina_ghost_delay := 0.0
const GHOST_DELAY := 0.4
const GHOST_DRAIN_SPEED := 1.2

# Stamina bar layout — aligned with health bar fill, 85% length
const STAM_BAR_X := 138.0
const STAM_BAR_Y := 40.0
const STAM_BAR_W := 200.0
const STAM_BAR_H := 10.0
const STAM_BORDER := 2.0
const STAM_CORNER_RADIUS := 4.0

const HUD_BAR_PATH := "res://Assets/sprites/Medieval_Castle_Asset_Pack/HUD/bar.png"
const HUD_BG_PATH := "res://Assets/sprites/Medieval_Castle_Asset_Pack/HUD/bar_background.png"
const HUD_HP_PATH := "res://Assets/sprites/Medieval_Castle_Asset_Pack/HUD/health_bar.png"
const HUD_WEAPON_PATH := "res://Assets/sprites/Medieval_Castle_Asset_Pack/HUD/weapon_icon.png"
const HUD_FILL_MAX_W := 240.0

const BAR_MASK_SHADER := "
shader_type canvas_item;
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = step(UV.x, ratio);
	COLOR = tex * mask;
}
"


# ═══════════════════════════════════════════
#  STATE QUERIES
# ═══════════════════════════════════════════

func _is_locked() -> bool:
	return state in [State.ATTACK, State.DASH, State.PARRY, State.HURT, State.DEAD, State.LEDGE_CLIMB]

func _is_grappling() -> bool:
	return grapple_state in [GrappleState.THROW, GrappleState.PULL, GrappleState.PULL_ENEMY]

func _is_action_locked() -> bool:
	return _is_locked() or _is_grappling()


# ═══════════════════════════════════════════
#  READY
# ═══════════════════════════════════════════

func _ready():
	add_to_group("Player")

	for anim in ["Attack", "Attack2", "AttackCombo2hit", "CrouchAttack", "Roll", "Dash", "Death", "Hit", "WallClimbNoMovement", "TurnAround", "JumpFallInbetween"]:
		if sprite.sprite_frames.has_animation(anim):
			sprite.sprite_frames.set_animation_loop(anim, false)

	_hitbox_base_x = hitbox_shape.position.x
	_body_base_x = body_shape.position.x
	sprite.animation_finished.connect(_on_animation_finished)
	_setup_attack_hitbox()
	_setup_pickup_area()
	_setup_health_ui()
	_setup_stamina_ui()
	_setup_grapple()
	_setup_ledge_rays()

	if camera != null:
		camera.offset = CAMERA_BASE_OFFSET

	_change_state(State.IDLE)


# ═══════════════════════════════════════════
#  SETUP (hitbox, HUD, grapple visuals)
# ═══════════════════════════════════════════

func _setup_attack_hitbox():
	attack_hitbox = Area2D.new()
	attack_hitbox.collision_layer = 0
	attack_hitbox.collision_mask = 8
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false

	# Reparent scene collision shapes into the Area2D
	hitbox_shape.get_parent().remove_child(hitbox_shape)
	hitbox_shape.disabled = true
	attack_hitbox.add_child(hitbox_shape)

	crouch_hitbox_shape.get_parent().remove_child(crouch_hitbox_shape)
	crouch_hitbox_shape.disabled = true
	attack_hitbox.add_child(crouch_hitbox_shape)

	add_child(attack_hitbox)


func _enable_attack_hitbox(crouching := false):
	if crouching:
		crouch_hitbox_shape.disabled = false
	else:
		hitbox_shape.disabled = false
	attack_hitbox.monitoring = true


func _disable_attack_hitbox():
	hitbox_shape.disabled = true
	crouch_hitbox_shape.disabled = true
	attack_hitbox.monitoring = false


func _setup_pickup_area():
	var pickup := Area2D.new()
	pickup.collision_layer = 2
	pickup.collision_mask = 0
	pickup.monitorable = true
	pickup.monitoring = false
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	col.shape = circle
	col.position = Vector2(0, -18)
	pickup.add_child(col)
	add_child(pickup)


func _create_bar_shader(initial_ratio: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = BAR_MASK_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("ratio", initial_ratio)
	return mat


func _setup_health_ui():
	weapon_icon = TextureRect.new()
	weapon_icon.texture = load(HUD_WEAPON_PATH)
	weapon_icon.position = Vector2(4, 4)
	weapon_icon.scale = Vector2(2, 2)
	canvas.add_child(weapon_icon)

	# Bar frame sits right of weapon icon (112px wide at 2x) with small gap
	# Frame is 118x13 at 1x, stretched 2.4x wide to be longer than stamina bar
	var frame_pos := Vector2(116, 10)
	var hp_scale := Vector2(2.4, 2.0)
	# Fill inset: 9px right * 2.4, 3px down * 2.0
	var fill_pos := Vector2(frame_pos.x + 22, frame_pos.y + 6)

	var hp_bg := TextureRect.new()
	hp_bg.texture = load(HUD_BG_PATH)
	hp_bg.position = fill_pos
	hp_bg.scale = hp_scale
	canvas.add_child(hp_bg)

	health_bar_ghost = TextureRect.new()
	health_bar_ghost.texture = load(HUD_HP_PATH)
	health_bar_ghost.position = fill_pos
	health_bar_ghost.scale = hp_scale
	health_bar_ghost.modulate = Color(1.0, 0.9, 0.5, 0.7)
	health_bar_ghost.material = _create_bar_shader(1.0)
	canvas.add_child(health_bar_ghost)

	health_bar_fill = TextureRect.new()
	health_bar_fill.texture = load(HUD_HP_PATH)
	health_bar_fill.position = fill_pos
	health_bar_fill.scale = hp_scale
	health_bar_fill.material = _create_bar_shader(1.0)
	canvas.add_child(health_bar_fill)

	# Frame drawn last (on top) so borders overlap fill edges
	health_bar_frame = TextureRect.new()
	health_bar_frame.texture = load(HUD_BAR_PATH)
	health_bar_frame.position = frame_pos
	health_bar_frame.scale = hp_scale
	canvas.add_child(health_bar_frame)



func _make_rounded_panel(col: Color, radius: float) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _setup_stamina_ui():
	var total_w := STAM_BAR_W + STAM_BORDER * 2.0
	var total_h := STAM_BAR_H + STAM_BORDER * 2.0
	var r := STAM_CORNER_RADIUS

	# Outline border
	stam_outline = _make_rounded_panel(Color(0.18, 0.18, 0.22, 0.9), r + STAM_BORDER)
	stam_outline.size = Vector2(total_w, total_h)
	stam_outline.position = Vector2(STAM_BAR_X, STAM_BAR_Y)
	canvas.add_child(stam_outline)

	# Dark background
	stam_bg = _make_rounded_panel(Color(0.08, 0.08, 0.1, 0.85), r)
	stam_bg.size = Vector2(STAM_BAR_W, STAM_BAR_H)
	stam_bg.position = Vector2(STAM_BAR_X + STAM_BORDER, STAM_BAR_Y + STAM_BORDER)
	canvas.add_child(stam_bg)

	# Ghost trail (shows where stamina was before spending)
	stam_ghost = _make_rounded_panel(Color(0.45, 0.7, 0.85, 0.4), r)
	stam_ghost.size = Vector2(STAM_BAR_W, STAM_BAR_H)
	stam_ghost.position = Vector2(STAM_BAR_X + STAM_BORDER, STAM_BAR_Y + STAM_BORDER)
	canvas.add_child(stam_ghost)

	# Fill bar
	stam_fill = _make_rounded_panel(Color(0.2, 0.65, 0.85), r)
	stam_fill.size = Vector2(STAM_BAR_W, STAM_BAR_H)
	stam_fill.position = Vector2(STAM_BAR_X + STAM_BORDER, STAM_BAR_Y + STAM_BORDER)
	canvas.add_child(stam_fill)


func _setup_grapple():
	grapple_line = Line2D.new()
	grapple_line.width = 1.5
	grapple_line.default_color = Color(0.78, 0.75, 0.65, 0.95)
	grapple_line.visible = false
	grapple_line.top_level = true
	grapple_line.z_index = 4
	grapple_line.antialiased = true
	add_child(grapple_line)

	grapple_hook_tip = Polygon2D.new()
	grapple_hook_tip.polygon = PackedVector2Array([
		Vector2(6, 0), Vector2(-1, -3), Vector2(-3, -2),
		Vector2(0, 0),
		Vector2(-3, 2), Vector2(-1, 3)
	])
	grapple_hook_tip.color = Color(0.92, 0.88, 0.78)
	grapple_hook_tip.visible = false
	grapple_hook_tip.top_level = true
	grapple_hook_tip.z_index = 5
	add_child(grapple_hook_tip)


func _setup_ledge_rays():
	# Upper ray: checks for air above the ledge (should NOT collide)
	ledge_ray_upper = RayCast2D.new()
	ledge_ray_upper.position = Vector2(0.0, -42.0)
	ledge_ray_upper.target_position = Vector2(14.0, 0.0)
	ledge_ray_upper.collision_mask = 2
	ledge_ray_upper.enabled = true
	add_child(ledge_ray_upper)

	# Lower ray: checks for wall face (should collide)
	ledge_ray_lower = RayCast2D.new()
	ledge_ray_lower.position = Vector2(0.0, -30.0)
	ledge_ray_lower.target_position = Vector2(14.0, 0.0)
	ledge_ray_lower.collision_mask = 2
	ledge_ray_lower.enabled = true
	add_child(ledge_ray_lower)


# ═══════════════════════════════════════════
#  MAIN STATE MACHINE — transitions
# ═══════════════════════════════════════════

func _change_state(new_state: State):
	var old := state
	if old == new_state:
		return
	blast_knockback = false

	# --- EXIT old state ---
	match old:
		State.ATTACK:
			_disable_attack_hitbox()
			attack_hit_bodies.clear()
		State.DASH:
			collision_layer = 2
		State.HURT:
			pass

	prev_state = old
	state = new_state

	# --- ENTER new state ---
	match new_state:
		State.FALL:
			if old == State.JUMP:
				sprite.play("JumpFallInbetween")
		State.LEDGE_GRAB:
			velocity = Vector2.ZERO
		State.LEDGE_CLIMB:
			velocity = Vector2.ZERO
			ledge_climb_timer = LEDGE_CLIMB_DURATION
		State.DASH:
			dash_move_timer = DASH_DURATION
			dash_move_dir = facing_dir
			dash_ghost_timer = 0.0
			collision_layer = 0
			_spawn_dash_ghost()
		State.HURT:
			hurt_timer = HURT_STUN
		State.DEAD:
			_disable_attack_hitbox()

	_resolve_animation()


## Pick the correct animation for the current state + grapple state
func _resolve_animation():
	# Grapple overrides movement animations during pull
	if grapple_state == GrappleState.PULL:
		play_anim("Slide")
		return

	# Blast knockback override
	if blast_knockback:
		play_anim("Dash")
		return

	# Double-jump roll: let animation finish uninterrupted
	if double_jump_rolling and sprite.animation == "Roll" and sprite.is_playing():
		return

	# Let cosmetic transition animations finish (locked states override them)
	if not _is_locked() and sprite.is_playing():
		if sprite.animation in ["TurnAround", "JumpFallInbetween"]:
			return

	match state:
		State.IDLE:
			play_anim("Idle")
		State.RUN:
			play_anim("Run")
		State.JUMP:
			play_anim("Jump")
		State.FALL:
			play_anim("Fall")
		State.WALL_SLIDE:
			play_anim("WallSlide")
		State.LEDGE_GRAB:
			play_anim("WallHang")
		State.LEDGE_CLIMB:
			play_anim("WallClimbNoMovement")
		State.CROUCH:
			play_anim("Crouch")
		State.CROUCH_WALK:
			play_anim("CrouchWalk")
		State.ATTACK:
			pass  # Handled by combo logic
		State.DASH:
			play_anim("Dash")
		State.PARRY:
			pass  # Handled by parry logic
		State.HURT:
			play_anim("Hit")
		State.DEAD:
			play_anim("Death")


## Resolve what free state we should be in from physics
func _resolve_free_state():
	if not is_on_floor():
		if velocity.y < 0.0:
			_change_state(State.JUMP)
		else:
			_change_state(State.FALL)
		return

	if Input.is_action_pressed("Crouch"):
		if absf(velocity.x) > 5.0:
			_change_state(State.CROUCH_WALK)
		else:
			_change_state(State.CROUCH)
		return

	if absf(velocity.x) > 5.0:
		_change_state(State.RUN)
	else:
		_change_state(State.IDLE)


# ═══════════════════════════════════════════
#  GRAPPLE STATE MACHINE — transitions
# ═══════════════════════════════════════════

func _change_grapple_state(new_gs: GrappleState):
	var old_gs := grapple_state
	if old_gs == new_gs:
		return

	# --- EXIT old grapple state ---
	match old_gs:
		GrappleState.THROW:
			pass
		GrappleState.PULL, GrappleState.PULL_ENEMY:
			grapple_hooked_enemy = null
			sprite.rotation = 0.0

	grapple_state = new_gs

	# --- ENTER new grapple state ---
	match new_gs:
		GrappleState.NONE:
			_hide_grapple_visuals()
		GrappleState.THROW:
			grapple_has_reset_air = false
			grapple_hook_flying = true
			grapple_hook_flight_timer = 0.0
			grapple_whiffing = false
			grapple_hook_pos = _grapple_hand_pos()
			grapple_hook_tip.global_position = grapple_hook_pos
			grapple_hook_tip.rotation = grapple_hook_vel.angle()
			grapple_line.clear_points()
			_update_rope_visuals()
			grapple_line.visible = true
			grapple_hook_tip.visible = true
		GrappleState.PULL:
			# Initialize swing: rope length = current distance to anchor
			var hand := _grapple_hand_pos()
			grapple_rope_length = hand.distance_to(grapple_point)
			grapple_swing_timer = GRAPPLE_MAX_SWING_TIME
			grapple_hook_tip.visible = true
		GrappleState.PULL_ENEMY:
			grapple_swing_timer = GRAPPLE_MAX_SWING_TIME
			grapple_hook_tip.visible = true
		GrappleState.COOLDOWN:
			grapple_cooldown_timer = GRAPPLE_COOLDOWN
			_hide_grapple_visuals()
			grapple_hooked_enemy = null


# ═══════════════════════════════════════════
#  PHYSICS MAIN
# ═══════════════════════════════════════════

func _physics_process(delta: float):
	if state == State.DEAD:
		return

	# Hit stop — freeze everything
	if hitstop_timer > 0.0:
		hitstop_timer -= delta
		# Keep rope visuals synced during hitstop
		if grapple_state != GrappleState.NONE:
			_update_rope_visuals()
		return

	_update_timers(delta)
	_update_invincibility(delta)
	_update_stamina(delta)
	_update_ghost_bars(delta)
	_update_look_pan(delta)
	_update_screen_shake(delta)
	_update_coyote(delta)
	var fs := float(facing_dir)
	hitbox_shape.position.x = _hitbox_base_x * fs
	body_shape.position.x = _body_base_x * fs

	# Gravity (disabled during grapple pull, dash, and ledge grab)
	var grapple_active := grapple_state in [GrappleState.PULL, GrappleState.THROW]
	var on_ledge := state in [State.LEDGE_GRAB, State.LEDGE_CLIMB]
	if not grapple_active and not on_ledge:
		if not is_on_floor():
			velocity.y += float(gravity) * delta

	# --- Update grapple sub-machine (runs alongside main state) ---
	_update_grapple_machine(delta)

	# Update ledge ray directions
	_update_ledge_rays()

	# --- Update main state ---
	if not _is_grappling():
		match state:
			State.HURT:
				move_and_slide()
				return
			State.ATTACK:
				_state_attack(delta)
			State.PARRY:
				_state_parry(delta)
			State.DASH:
				_state_dash(delta)
			State.WALL_SLIDE:
				_state_wall_slide(delta)
			State.LEDGE_GRAB:
				_state_ledge_grab(delta)
			State.LEDGE_CLIMB:
				_state_ledge_climb(delta)
			_:
				_state_free(delta)

	sprite.flip_h = facing_dir < 0
	move_and_slide()

	# Enforce rigid-rod constraint after move_and_slide — it can push player off the circle.
	# Strip the radial velocity component using dot product: V_tangent = V - (V · r̂) * r̂
	# This ensures the player only moves along the arc of the swing circle.
	if grapple_state == GrappleState.PULL:
		var hand := _grapple_hand_pos()
		var to_anchor := grapple_point - hand
		var dist := to_anchor.length()
		if dist > 1.0:
			var rope_dir := to_anchor.normalized()
			global_position = grapple_point - rope_dir * grapple_rope_length + Vector2(0.0, 18.0)
			var vel_radial := velocity.dot(rope_dir)
			velocity -= rope_dir * vel_radial
	elif grapple_state == GrappleState.PULL_ENEMY and is_instance_valid(grapple_hooked_enemy):
		var hand := _grapple_hand_pos()
		var to_anchor := grapple_point - hand
		var dist := to_anchor.length()
		if dist > 1.0:
			var rope_dir := to_anchor.normalized()
			var vel_radial := velocity.dot(rope_dir)
			# Only keep the radial component pointing toward the enemy (strip outward/tangent drift)
			velocity = rope_dir * maxf(vel_radial, 0.0)

	_check_enemy_contact()


# ═══════════════════════════════════════════
#  STATE: FREE (Idle / Run / Jump / Fall / Crouch)
# ═══════════════════════════════════════════

func _state_free(delta: float):
	_handle_grapple_input()
	if _is_grappling(): return
	_handle_dash_input()
	if _is_locked(): return
	_handle_attack_input()
	if _is_locked(): return
	_handle_parry_input()
	if _is_locked(): return
	_handle_grenade_input()
	_handle_blast_input()
	_handle_jump_input()

	# Ledge grab check (while falling near a wall)
	if not is_on_floor() and velocity.y >= 0.0:
		if _try_ledge_grab():
			return

	# Wall slide check
	if not is_on_floor() and is_on_wall() and velocity.y > 0.0:
		double_jump_rolling = false
		sprite.speed_scale = 1.0
		_change_state(State.WALL_SLIDE)
		var wall_dir := -get_wall_normal().x
		facing_dir = -1 if wall_dir > 0.0 else 1
		return

	# Movement
	var crouching := Input.is_action_pressed("Crouch") and is_on_floor()
	var dir := Input.get_axis("Move_Left", "Move_Right")
	var target_speed := CROUCH_SPEED if crouching else SPEED

	var accel : float
	var decel : float
	if is_on_floor():
		accel = GROUND_ACCEL
		decel = GROUND_DECEL
	else:
		accel = AIR_ACCEL
		decel = AIR_DECEL

	if dir != 0.0:
		var new_facing := 1 if dir > 0.0 else -1
		if new_facing != facing_dir and sprite.animation != "TurnAround":
			if is_on_floor() and not crouching:
				turn_pending_dir = new_facing
				sprite.play("TurnAround", 1.2)
			else:
				facing_dir = new_facing
		velocity.x = move_toward(velocity.x, dir * target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)

	# Resolve movement sub-state for animation
	if not is_on_floor():
		# Dead zone at apex prevents rapid JUMP↔FALL toggling
		if velocity.y < -20.0:
			_change_state(State.JUMP)
		elif velocity.y > 20.0:
			_change_state(State.FALL)
		elif state != State.JUMP and state != State.FALL:
			_change_state(State.FALL)
		# else: in dead zone, keep current JUMP or FALL state
	elif crouching:
		if absf(velocity.x) > 5.0:
			_change_state(State.CROUCH_WALK)
		else:
			_change_state(State.CROUCH)
	elif absf(velocity.x) > 5.0:
		_change_state(State.RUN)
	else:
		_change_state(State.IDLE)


# ═══════════════════════════════════════════
#  STATE: WALL SLIDE
# ═══════════════════════════════════════════

func _state_wall_slide(_delta: float):
	velocity.y = minf(velocity.y, 80.0)

	# Ledge grab from wall slide
	if _try_ledge_grab():
		return

	if Input.is_action_just_pressed("Jump"):
		var dir := -get_wall_normal().x
		velocity = Vector2(dir * WALL_JUMP_FORCE.x, WALL_JUMP_FORCE.y)
		facing_dir = -1 if dir > 0.0 else 1
		_change_state(State.JUMP)
		return

	if is_on_floor() or not is_on_wall() or velocity.y <= 0.0:
		_resolve_free_state()
		return

	_handle_grapple_input()


# ═══════════════════════════════════════════
#  LEDGE GRAB
# ═══════════════════════════════════════════

func _update_ledge_rays():
	ledge_ray_upper.target_position.x = float(facing_dir) * 14.0
	ledge_ray_lower.target_position.x = float(facing_dir) * 14.0


func _try_ledge_grab() -> bool:
	# Lower ray must hit wall, upper ray must be clear (air above ledge)
	if not ledge_ray_lower.is_colliding():
		return false
	if ledge_ray_upper.is_colliding():
		return false

	# Determine wall direction from the lower ray hit
	var hit_normal : Vector2 = ledge_ray_lower.get_collision_normal()
	var wall_dir := int(-signf(hit_normal.x))
	if wall_dir == 0:
		return false

	ledge_grab_wall_dir = wall_dir
	facing_dir = wall_dir

	# Snap player to the ledge: offset into the wall slightly
	var hit_point : Vector2 = ledge_ray_lower.get_collision_point()
	global_position.x = hit_point.x - float(wall_dir) * LEDGE_GRAB_SIDE_OFFSET
	global_position.y += LEDGE_GRAB_UP_OFFSET

	# Calculate climb target: top of the ledge
	# Climb moves the player up by about the capsule height and forward onto the platform
	ledge_climb_target = global_position + Vector2(float(wall_dir) * 16.0, -36.0)

	_change_state(State.LEDGE_GRAB)
	return true


func _state_ledge_grab(_delta: float):
	velocity = Vector2.ZERO

	# Jump off (up or away from wall)
	if Input.is_action_just_pressed("Jump"):
		velocity = LEDGE_JUMP_FORCE
		coyote_timer = 0.0
		_change_state(State.JUMP)
		return

	# Climb up (press up or toward the wall)
	var h := Input.get_axis("Move_Left", "Move_Right")
	if Input.is_action_just_pressed("Jump") == false:
		if (ledge_grab_wall_dir == 1 and h > 0.3) or \
		   (ledge_grab_wall_dir == -1 and h < -0.3) or \
		   Input.is_action_pressed("Jump"):
			_change_state(State.LEDGE_CLIMB)
			return

	# Drop down (press down or away from wall)
	if Input.is_action_pressed("Crouch"):
		_resolve_free_state()
		return
	if (ledge_grab_wall_dir == 1 and h < -0.3) or \
	   (ledge_grab_wall_dir == -1 and h > 0.3):
		_resolve_free_state()
		return

	# Grapple cancel
	_handle_grapple_input()


func _state_ledge_climb(delta: float):
	velocity = Vector2.ZERO

	ledge_climb_timer -= delta
	if ledge_climb_timer <= 0.0:
		_finish_ledge_climb()
		return

	# Smoothly move toward climb target
	var t := 1.0 - (ledge_climb_timer / LEDGE_CLIMB_DURATION)
	global_position = global_position.lerp(ledge_climb_target, t * delta * 8.0)


func _finish_ledge_climb():
	global_position = ledge_climb_target
	# Strong downward push guarantees floor contact in a single call
	velocity = Vector2(0.0, 600.0)
	move_and_slide()
	velocity = Vector2.ZERO
	_change_state(State.IDLE)


# ═══════════════════════════════════════════
#  STATE: ATTACK
# ═══════════════════════════════════════════

func _state_attack(delta: float):
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, GROUND_DECEL * delta)

	# Allow grapple cancel from attack (Messenger-style)
	_handle_grapple_input()
	if _is_grappling(): return

	for body in attack_hitbox.get_overlapping_bodies():
		if body == self or body in attack_hit_bodies:
			continue
		if body.is_in_group("Enemy") and body.has_method("take_damage"):
			attack_hit_bodies.append(body)
			body.take_damage(attack_damage)
			# Halve momentum on hit in the air
			if not is_on_floor():
				velocity.x *= 0.5
			_trigger_hitstop(HITSTOP_ATTACK)
			_trigger_shake(SHAKE_ATTACK_STRENGTH, SHAKE_ATTACK_DURATION)

	if Input.is_action_just_pressed("Attack") and combo_timer > 0.0:
		combo_step += 1


# ═══════════════════════════════════════════
#  STATE: PARRY
# ═══════════════════════════════════════════

func _handle_parry_input():
	if not Input.is_action_just_pressed("parry"):
		return
	if not is_on_floor():
		return
	_change_state(State.PARRY)
	velocity.x = 0.0
	parry_timer = PARRY_TOTAL_TIME
	parry_window_active = true
	parry_succeeded = false
	play_anim("Parry")


func _state_parry(delta: float):
	velocity.x = 0.0
	parry_timer -= delta

	# Parry window expires after PARRY_WINDOW seconds
	if parry_window_active and parry_timer <= PARRY_TOTAL_TIME - PARRY_WINDOW:
		parry_window_active = false

	# Parry state ends
	if parry_timer <= 0.0:
		_change_state(State.IDLE)


func _try_parry(attacker: Node2D) -> bool:
	if state != State.PARRY or not parry_window_active:
		return false
	parry_succeeded = true
	parry_window_active = false
	play_anim("ParryW")
	_trigger_hitstop(0.15)
	_trigger_shake(SHAKE_ATTACK_STRENGTH * 1.5, SHAKE_ATTACK_DURATION)

	# Deal parry damage back to attacker
	if attacker.has_method("take_damage"):
		attacker.take_damage(PARRY_DAMAGE)

	# Blasphemous-style time slow
	Engine.time_scale = 0.15
	get_tree().create_timer(0.2, true, false, true).timeout.connect(_restore_time_scale)

	# Extend parry state to show success animation
	parry_timer = 0.3
	return true


func _restore_time_scale():
	Engine.time_scale = 1.0


# ═══════════════════════════════════════════
#  STATE: DASH (Hyper Light Drifter style)
# ═══════════════════════════════════════════

func _state_dash(delta: float):
	velocity.x = float(dash_move_dir) * DASH_MOVE_SPEED
	velocity.y = 0.0
	dash_move_timer -= delta

	# Spawn ghost trail at intervals
	dash_ghost_timer -= delta
	if dash_ghost_timer <= 0.0:
		dash_ghost_timer += DASH_GHOST_INTERVAL
		_spawn_dash_ghost()

	if dash_move_timer <= 0.0:
		collision_layer = 2
		_resolve_free_state()


func _spawn_dash_ghost():
	var ghost := Sprite2D.new()
	var anim_name := sprite.animation
	var frame_idx := sprite.frame
	ghost.texture = sprite.sprite_frames.get_frame_texture(anim_name, frame_idx)
	ghost.global_position = sprite.global_position
	ghost.flip_h = sprite.flip_h
	ghost.modulate = DASH_GHOST_COLOR
	ghost.z_index = z_index - 1
	get_tree().current_scene.add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, DASH_GHOST_FADE_TIME).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ghost, "scale", Vector2(1.1, 1.1), DASH_GHOST_FADE_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ghost.queue_free)


# ═══════════════════════════════════════════
#  GRAPPLE STATE MACHINE — update
# ═══════════════════════════════════════════

func _grapple_hand_pos() -> Vector2:
	return global_position + Vector2(0.0, -18.0)


func _hide_grapple_visuals():
	grapple_line.clear_points()
	grapple_line.visible = false
	grapple_hook_tip.visible = false


func _update_grapple_machine(delta: float):
	match grapple_state:
		GrappleState.NONE:
			pass
		GrappleState.THROW:
			_grapple_throw_update(delta)
		GrappleState.PULL:
			_grapple_pull_update(delta)
		GrappleState.PULL_ENEMY:
			_grapple_pull_enemy_update(delta)
		GrappleState.COOLDOWN:
			if grapple_cooldown_timer <= 0.0:
				_change_grapple_state(GrappleState.NONE)


## THROW — hook projectile flies outward, visible rope trails behind it
func _grapple_throw_update(delta: float):
	# Cancel: release grapple button or press jump
	if not Input.is_action_pressed("Grapple"):
		_change_grapple_state(GrappleState.COOLDOWN)
		_resolve_free_state()
		return
	if Input.is_action_just_pressed("Jump"):
		_grapple_launch()
		return

	if grapple_whiffing:
		# Whiff retract: pull hook back toward hand
		grapple_whiff_timer -= delta
		if grapple_whiff_timer <= 0.0:
			_change_grapple_state(GrappleState.COOLDOWN)
			_resolve_free_state()
			return
		var hand := _grapple_hand_pos()
		grapple_hook_pos = grapple_hook_pos.lerp(hand, 1.0 - pow(0.02, delta))
		grapple_hook_tip.global_position = grapple_hook_pos
		_update_rope_visuals()
		return

	if grapple_hook_flying:
		# Apply gravity to hook velocity
		grapple_hook_vel.y += GRAPPLE_HOOK_GRAVITY * delta
		var motion := grapple_hook_vel * delta
		var next_pos := grapple_hook_pos + motion

		# Raycast along this frame's motion to detect hits
		var space := get_world_2d().direct_space_state
		var my_rid := get_rid()

		# Check enemies first (mask 8)
		var eq := PhysicsRayQueryParameters2D.create(grapple_hook_pos, next_pos, 8)
		eq.exclude = [my_rid]
		eq.hit_from_inside = false
		var ehit := space.intersect_ray(eq)
		if ehit:
			var body := ehit.collider as CharacterBody2D
			if body != null and body.is_in_group("Enemy"):
				grapple_point = ehit.position
				grapple_hooked_enemy = body
				grapple_hook_pos = ehit.position
				grapple_hook_flying = false
				if body.has_method("_hurt") and body.get("state") != null:
					body.velocity = Vector2.ZERO
				_change_grapple_state(GrappleState.PULL_ENEMY)
				_resolve_animation()
				return

		# Check terrain (mask 3)
		var tq := PhysicsRayQueryParameters2D.create(grapple_hook_pos, next_pos, 3)
		tq.exclude = [my_rid]
		tq.hit_from_inside = false
		var thit := space.intersect_ray(tq)
		if thit:
			var hit_normal : Vector2 = thit.normal
			grapple_point = thit.position + hit_normal * 10.0
			grapple_hooked_enemy = null
			grapple_hook_pos = thit.position
			grapple_hook_flying = false
			_change_grapple_state(GrappleState.PULL)
			_resolve_animation()
			return

		# No hit — advance hook position
		grapple_hook_pos = next_pos
		grapple_hook_flight_timer += delta

		# Whiff if hook has been flying too long
		if grapple_hook_flight_timer >= GRAPPLE_HOOK_MAX_TIME:
			grapple_whiffing = true
			grapple_whiff_timer = 0.12
			# Partial stamina refund for whiff
			stamina += STAMINA_COST_GRAPPLE * 0.5
			stamina = minf(stamina, MAX_STAMINA)

		grapple_hook_tip.global_position = grapple_hook_pos
		grapple_hook_tip.rotation = grapple_hook_vel.angle()
		grapple_aim_dir = grapple_hook_vel.normalized()
		_update_rope_visuals()


## PULL (SWING) — SpeedRunners-style pendulum with tangent velocity projection
func _grapple_pull_update(delta: float):
	# --- Cancel inputs (all preserve momentum) ---
	# Release grapple button = release rope (SpeedRunners hold-to-swing)
	if not Input.is_action_pressed("Grapple"):
		_grapple_launch()
		return
	if Input.is_action_just_pressed("Jump"):
		_grapple_launch()
		return
	if Input.is_action_just_pressed("Attack") and _use_stamina(STAMINA_COST_ATTACK):
		var launch_vel := velocity * 0.6
		_change_grapple_state(GrappleState.COOLDOWN)
		velocity = launch_vel
		_change_state(State.ATTACK)
		combo_timer = COMBO_WINDOW
		combo_step = 0
		attack_hit_bodies.clear()
		_enable_attack_hitbox()
		play_anim("Attack")
		return
	if Input.is_action_just_pressed("Dash") and _use_stamina(STAMINA_COST_DASH):
		_change_grapple_state(GrappleState.COOLDOWN)
		_change_state(State.DASH)
		return

	# Timeout
	grapple_swing_timer -= delta
	if grapple_swing_timer <= 0.0:
		_grapple_launch()
		return

	# --- Swing physics (SpeedRunners fixed-distance pendulum) ---
	var hand := _grapple_hand_pos()
	var to_anchor := grapple_point - hand
	var dist := to_anchor.length()
	if dist < 1.0:
		dist = 1.0

	# Rope length is fixed — no W/S adjustment

	# --- Fixed-distance constraint (rigid rod, not bungee) ---
	# r̂ = normalized vector from player hand toward the anchor
	var rope_dir := to_anchor.normalized()

	# 1) Snap position: player is ALWAYS exactly rope_length from anchor.
	#    This is the core SpeedRunners feel — the rope never stretches or compresses.
	var target_hand := grapple_point - rope_dir * grapple_rope_length
	global_position = target_hand + Vector2(0.0, 18.0)

	# 2) Project velocity onto the tangent of the swing circle.
	#    Remove ALL radial component (both inward and outward):
	#    V_tangent = V_total − (V_total · r̂) * r̂
	var vel_radial := velocity.dot(rope_dir)
	velocity -= rope_dir * vel_radial

	# 3) Apply gravity as tangential acceleration only.
	#    Real gravity is (0, g). Its tangential component along the circle:
	#    a_tangent = g − (g · r̂) * r̂
	var gravity_vec := Vector2(0.0, float(gravity) * GRAPPLE_SWING_GRAVITY_MULT)
	var grav_radial := gravity_vec.dot(rope_dir)
	var grav_tangent := gravity_vec - rope_dir * grav_radial
	velocity += grav_tangent * delta

	# 4) A/D input pumps the swing (tangential boost)
	var h := Input.get_axis("Move_Left", "Move_Right")
	if absf(h) > 0.1:
		var tangent := Vector2(-rope_dir.y, rope_dir.x)
		velocity += tangent * h * GRAPPLE_SWING_PUMP * delta

	# Reset air actions once during swing
	if not grapple_has_reset_air:
		coyote_timer = COYOTE_TIME
		air_jumps_left = MAX_AIR_JUMPS
		grapple_has_reset_air = true

	# Flip facing toward swing direction
	if absf(velocity.x) > 10.0:
		facing_dir = -1 if velocity.x < 0.0 else 1

	# Keep hook tip at anchor
	grapple_hook_tip.global_position = grapple_point
	_update_rope_visuals()
	play_anim("Slide")


## PULL_ENEMY — player is propelled toward enemy (direct pull, not swing)
func _grapple_pull_enemy_update(delta: float):
	# --- Cancel inputs (all preserve momentum) ---
	# Release grapple button = release (hold-to-swing)
	if not Input.is_action_pressed("Grapple"):
		_grapple_launch()
		return
	if Input.is_action_just_pressed("Jump"):
		_grapple_launch()
		return
	if Input.is_action_just_pressed("Attack") and _use_stamina(STAMINA_COST_ATTACK):
		var launch_vel := velocity * 0.6
		_change_grapple_state(GrappleState.COOLDOWN)
		velocity = launch_vel
		_change_state(State.ATTACK)
		combo_timer = COMBO_WINDOW
		combo_step = 0
		attack_hit_bodies.clear()
		_enable_attack_hitbox()
		play_anim("Attack")
		return
	if Input.is_action_just_pressed("Dash") and _use_stamina(STAMINA_COST_DASH):
		_change_grapple_state(GrappleState.COOLDOWN)
		_change_state(State.DASH)
		return

	# Timeout
	grapple_swing_timer -= delta
	if grapple_swing_timer <= 0.0:
		_grapple_launch()
		return

	# Enemy invalid or dead — launch with current momentum
	if not is_instance_valid(grapple_hooked_enemy):
		_grapple_launch()
		return
	if grapple_hooked_enemy.has_method("_is_dead") and grapple_hooked_enemy._is_dead():
		_grapple_launch()
		return

	# --- Pull physics: player flies toward enemy ---
	var enemy_center := grapple_hooked_enemy.global_position + Vector2(0.0, -20.0)
	grapple_point = enemy_center
	var hand := _grapple_hand_pos()
	var to_hook := enemy_center - hand
	var dist := to_hook.length()

	# Arrived at enemy — snap attack (Messenger-style)
	if dist < GRAPPLE_ARRIVE_DIST + 8.0:
		_change_grapple_state(GrappleState.COOLDOWN)

		# Dead stop → immediate damage on the hooked enemy
		velocity = Vector2.ZERO
		_change_state(State.ATTACK)
		combo_timer = COMBO_WINDOW
		combo_step = 0
		attack_hit_bodies.clear()
		_enable_attack_hitbox()
		play_anim("Attack")

		# Instant hit on the grappled enemy — don't wait for hitbox overlap
		if is_instance_valid(grapple_hooked_enemy) and grapple_hooked_enemy.has_method("take_damage"):
			attack_hit_bodies.append(grapple_hooked_enemy)
			grapple_hooked_enemy.take_damage(attack_damage)

		# Punchy feedback
		_trigger_hitstop(HITSTOP_ATTACK * 2.5)
		_trigger_shake(SHAKE_ATTACK_STRENGTH * 2.5, SHAKE_ATTACK_DURATION * 2.0)

		# Bounce off — upward launch like cloudstep
		var kb_dir := signf(global_position.x - enemy_center.x)
		if kb_dir == 0.0:
			kb_dir = float(facing_dir)
		velocity = Vector2(kb_dir * 180.0, -340.0)
		coyote_timer = COYOTE_TIME
		return

	# Accelerate toward enemy
	var pull_dir := to_hook.normalized()
	var pull_speed := minf(dist / delta, GRAPPLE_ENEMY_PULL_SPEED)
	velocity = pull_dir * pull_speed

	# Reset air actions once during pull
	if not grapple_has_reset_air:
		coyote_timer = COYOTE_TIME
		grapple_has_reset_air = true

	# Flip facing toward enemy
	if absf(pull_dir.x) > 0.1:
		facing_dir = -1 if pull_dir.x < 0.0 else 1

	# Keep hook tip on enemy
	grapple_hook_tip.global_position = enemy_center
	_update_rope_visuals()
	play_anim("Slide")


# ═══════════════════════════════════════════
#  GRAPPLE — fire, launch, visuals
# ═══════════════════════════════════════════

func _handle_grapple_input():
	if not Input.is_action_just_pressed("Grapple"):
		return
	if state == State.HURT or state == State.DEAD:
		return
	if grapple_state != GrappleState.NONE:
		return
	if not _use_stamina(STAMINA_COST_GRAPPLE):
		return
	# Cancel attack/dash into grapple (Messenger-style interrupt)
	if state == State.ATTACK:
		_disable_attack_hitbox()
		attack_hit_bodies.clear()
	_fire_grapple()


func _fire_grapple():
	# --- Grenade-style arc: launch hook with velocity + gravity ---
	var facing := float(facing_dir)
	var angle_rad := deg_to_rad(GRENADE_THROW_ANGLE)
	grapple_hook_vel = Vector2(facing * GRAPPLE_HOOK_SPEED * cos(angle_rad), GRAPPLE_HOOK_SPEED * sin(angle_rad))
	grapple_aim_dir = grapple_hook_vel.normalized()
	grapple_point = Vector2.ZERO
	grapple_hooked_enemy = null
	_change_grapple_state(GrappleState.THROW)


func _grapple_launch():
	# SpeedRunners slingshot: preserve swing momentum with release boost
	var launch := velocity * GRAPPLE_RELEASE_BOOST
	# If moving slowly, give a minimum launch in the aimed direction
	if launch.length() < GRAPPLE_LAUNCH_SPEED * 0.5:
		launch = velocity.normalized() * GRAPPLE_LAUNCH_SPEED * 0.5 if velocity.length() > 1.0 else Vector2(0.0, -200.0)
	launch.y += GRAPPLE_LAUNCH_UP_BIAS * 0.5
	var h := Input.get_axis("Move_Left", "Move_Right")
	if absf(h) > 0.1:
		launch.x += h * GRAPPLE_LAUNCH_SPEED * 0.3

	velocity = launch
	coyote_timer = COYOTE_TIME * 1.5
	_change_grapple_state(GrappleState.COOLDOWN)
	_resolve_free_state()





func _update_rope_visuals():
	grapple_line.clear_points()
	grapple_line.visible = true
	var start := _grapple_hand_pos()
	var end_pt := grapple_hook_pos

	if grapple_state in [GrappleState.PULL, GrappleState.PULL_ENEMY]:
		end_pt = grapple_point
		if is_instance_valid(grapple_hooked_enemy):
			end_pt = grapple_hooked_enemy.global_position + Vector2(0.0, -20.0)

	var dist := start.distance_to(end_pt)
	var sag := clampf(dist * 0.012, 0.0, 2.5)
	for i in GRAPPLE_ROPE_SEGMENTS + 1:
		var t := float(i) / float(GRAPPLE_ROPE_SEGMENTS)
		var pt := start.lerp(end_pt, t)
		pt.y += sin(t * PI) * sag
		grapple_line.add_point(pt)


# ═══════════════════════════════════════════
#  INPUT HANDLERS
# ═══════════════════════════════════════════

func _handle_dash_input():
	if not Input.is_action_just_pressed("Dash"):
		return
	if state == State.ATTACK:
		return
	if not _use_stamina(STAMINA_COST_DASH):
		return
	_change_state(State.DASH)


func _handle_attack_input():
	if not Input.is_action_just_pressed("Attack"):
		return
	if state == State.DASH:
		return

	var cost := STAMINA_COST_ATTACK
	var crouching := Input.is_action_pressed("Crouch") and is_on_floor()
	if crouching:
		cost = STAMINA_COST_CROUCH_ATK
	elif combo_step == 1:
		cost = STAMINA_COST_ATTACK2
	elif combo_step >= 2:
		cost = STAMINA_COST_COMBO

	if not _use_stamina(cost):
		return

	# Instantly flip direction on attack — skip TurnAround animation
	var dir := Input.get_axis("Move_Left", "Move_Right")
	if dir != 0.0:
		var new_facing := 1 if dir > 0.0 else -1
		if new_facing != facing_dir:
			facing_dir = new_facing
	elif turn_pending_dir != 0:
		facing_dir = turn_pending_dir
	turn_pending_dir = 0

	_change_state(State.ATTACK)
	combo_timer = COMBO_WINDOW
	attack_hit_bodies.clear()
	_enable_attack_hitbox(crouching)

	if crouching:
		play_anim("CrouchAttack")
		return

	match combo_step:
		0:
			play_anim("Attack")
		1:
			play_anim("Attack2")
		2:
			play_anim("AttackCombo2hit")
		_:
			combo_step = 0
			play_anim("Attack")


func _handle_grenade_input():
	if not Input.is_action_just_pressed("throw"):
		return
	if state == State.DASH or state == State.HURT or grenade_cooldown_timer > 0.0:
		return
	if not _use_stamina(STAMINA_COST_GRENADE):
		return

	grenade_cooldown_timer = GRENADE_COOLDOWN

	var facing := float(facing_dir)
	var angle_rad := deg_to_rad(GRENADE_THROW_ANGLE)
	var throw_vel := Vector2(facing * GRENADE_THROW_SPEED * cos(angle_rad), GRENADE_THROW_SPEED * sin(angle_rad))

	var grenade_script := preload("res://Scripts/grenade.gd")
	var grenade : Area2D = Area2D.new()
	grenade.set_script(grenade_script)
	grenade.vel = throw_vel
	grenade.global_position = global_position + Vector2(facing * 10.0, -25.0)

	get_tree().current_scene.add_child(grenade)


func _handle_blast_input():
	if not Input.is_action_just_pressed("blast"):
		return
	if state == State.DASH or state == State.HURT or blast_cooldown_timer > 0.0:
		return
	if not _use_stamina(STAMINA_COST_BLAST):
		return

	blast_cooldown_timer = BLAST_COOLDOWN

	# Spawn blast effect at player position
	var blast_script := preload("res://Scripts/blast_effect.gd")
	var blast := Node2D.new()
	blast.set_script(blast_script)
	blast.damage = BLAST_DAMAGE
	blast.radius = BLAST_RADIUS
	blast.source_body = self
	blast.global_position = global_position + Vector2(0.0, -16.0)
	get_tree().current_scene.add_child(blast)

	# Knockback: push player away from nearest enemy or wall
	var facing := float(facing_dir)
	var kb_dir := -facing  # Default: push player backwards

	# Check for nearest enemy to push away from
	var space := get_world_2d().direct_space_state
	var chest := global_position + Vector2(0.0, -20.0)
	var enemy_query := PhysicsRayQueryParameters2D.create(
		chest, chest + Vector2(facing, 0.0) * BLAST_RADIUS, 8
	)
	enemy_query.exclude = [get_rid()]
	var enemy_hit := space.intersect_ray(enemy_query)
	if enemy_hit:
		kb_dir = signf(global_position.x - enemy_hit.position.x)
		if kb_dir == 0.0:
			kb_dir = -facing

	velocity = Vector2(kb_dir * GRAPPLE_LAUNCH_SPEED, GRAPPLE_LAUNCH_UP_BIAS)
	blast_knockback = true
	coyote_timer = COYOTE_TIME * 1.5
	_trigger_shake(SHAKE_ATTACK_STRENGTH * 2.0, SHAKE_ATTACK_DURATION * 2.0)
	_trigger_hitstop(HITSTOP_ATTACK)


func _handle_jump_input():
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = JUMP_BUFFER

	if Input.is_action_just_released("Jump") and velocity.y < 0.0 and state != State.WALL_SLIDE:
		velocity.y *= VARIABLE_JUMP_DAMPEN

	if not Input.is_action_just_pressed("Jump"):
		return

	var can_jump := is_on_floor() or coyote_timer > 0.0
	if can_jump:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		air_jumps_left = MAX_AIR_JUMPS
		_change_state(State.JUMP)
	elif air_jumps_left > 0:
		air_jumps_left -= 1
		velocity.y = DOUBLE_JUMP_VELOCITY
		jump_buffer_timer = 0.0
		double_jump_rolling = true
		_change_state(State.JUMP)
		sprite.speed_scale = 1.8
		play_anim("Roll")


# ═══════════════════════════════════════════
#  TIMERS
# ═══════════════════════════════════════════

func _update_timers(delta: float):
	if combo_timer > 0.0:
		combo_timer -= delta
	elif state != State.ATTACK:
		combo_step = 0

	if hurt_timer > 0.0:
		hurt_timer -= delta
		if hurt_timer <= 0.0 and state == State.HURT:
			_resolve_free_state()

	if grenade_cooldown_timer > 0.0:
		grenade_cooldown_timer -= delta
	if grapple_cooldown_timer > 0.0:
		grapple_cooldown_timer -= delta
	if blast_cooldown_timer > 0.0:
		blast_cooldown_timer -= delta
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta
	if stamina_flash_timer > 0.0:
		stamina_flash_timer -= delta


func _update_stamina(delta: float):
	if stamina_regen_cooldown > 0.0:
		if state != State.HURT:
			stamina_regen_cooldown -= delta
	elif stamina < MAX_STAMINA:
		stamina = minf(stamina + STAMINA_REGEN_RATE * delta, MAX_STAMINA)
	_update_stamina_ui()


func _update_coyote(delta: float):
	var on_floor_now := is_on_floor()
	if was_on_floor and not on_floor_now and velocity.y >= 0.0:
		coyote_timer = COYOTE_TIME
	elif on_floor_now:
		coyote_timer = 0.0
		air_jumps_left = MAX_AIR_JUMPS
		double_jump_rolling = false
		sprite.speed_scale = 1.0

	if coyote_timer > 0.0:
		coyote_timer -= delta

	was_on_floor = on_floor_now

	if on_floor_now and jump_buffer_timer > 0.0 and not _is_locked() and not _is_grappling():
		jump_buffer_timer = 0.0
		velocity.y = JUMP_VELOCITY
		air_jumps_left = MAX_AIR_JUMPS
		_change_state(State.JUMP)


func _update_invincibility(delta: float):
	if not is_invincible:
		return
	invincibility_timer -= delta
	sprite.modulate.a = 0.3 if fmod(invincibility_timer, 0.15) < 0.075 else 1.0
	if invincibility_timer <= 0.0:
		is_invincible = false
		sprite.modulate.a = 1.0


func _update_look_pan(delta: float):
	if camera == null:
		return

	# Determine look direction from input (only when standing still on floor)
	var wants_up := Input.is_action_pressed("look up")
	var wants_down := Input.is_action_pressed("Crouch")
	var h := Input.get_axis("Move_Left", "Move_Right")
	var is_still := is_on_floor() and absf(velocity.x) < 5.0 and absf(h) < 0.1
	var can_look := is_still and not _is_locked() and not _is_grappling() \
		and state not in [State.ATTACK, State.DASH, State.HURT, State.DEAD, \
		State.LEDGE_GRAB, State.LEDGE_CLIMB, State.CROUCH_WALK]

	var new_dir := 0
	if can_look:
		if wants_up and not wants_down:
			new_dir = -1  # look up (negative Y = up)
		elif wants_down and not wants_up:
			new_dir = 1   # look down (positive Y = down)

	# Track hold time and direction
	if new_dir != 0 and new_dir == look_direction:
		look_hold_timer += delta
	elif new_dir != 0:
		look_direction = new_dir
		look_hold_timer = 0.0
	else:
		look_direction = 0
		look_hold_timer = 0.0

	# Pan camera after delay
	var target_offset := 0.0
	if look_direction != 0 and look_hold_timer >= LOOK_PAN_DELAY:
		target_offset = float(look_direction) * LOOK_PAN_DISTANCE

	look_pan_offset = move_toward(look_pan_offset, target_offset, LOOK_PAN_SPEED * delta)

	# Apply to camera (only if not shaking — shake handles its own offset)
	if shake_timer <= 0.0:
		camera.offset = CAMERA_BASE_OFFSET + Vector2(0.0, look_pan_offset)


func _update_screen_shake(delta: float):
	if camera == null:
		return
	var base := CAMERA_BASE_OFFSET + Vector2(0.0, look_pan_offset)
	if shake_timer > 0.0:
		shake_timer -= delta
		var intensity := shake_strength * (shake_timer / maxf(shake_timer + delta, 0.001))
		camera.offset = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		) + base
		if shake_timer <= 0.0:
			camera.offset = base


# ═══════════════════════════════════════════
#  HUD UPDATES
# ═══════════════════════════════════════════

func _set_panel_color(panel: Panel, col: Color) -> void:
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = col


func _update_stamina_ui():
	var ratio := stamina / MAX_STAMINA
	stam_fill.size.x = STAM_BAR_W * ratio

	if stamina_flash_timer > 0.0:
		_set_panel_color(stam_fill, Color(1.0, 0.3, 0.3))
	elif ratio > 0.5:
		_set_panel_color(stam_fill, Color(0.2, 0.65, 0.85))
	elif ratio > 0.2:
		_set_panel_color(stam_fill, Color(0.85, 0.75, 0.2))
	else:
		_set_panel_color(stam_fill, Color(0.85, 0.2, 0.2))


func _update_ghost_bars(delta: float):
	# --- Health ghost ---
	var hp_ratio := float(health) / float(max_health)
	if health_ghost_delay > 0.0:
		health_ghost_delay -= delta
	else:
		if health_ghost_ratio > hp_ratio:
			health_ghost_ratio = maxf(health_ghost_ratio - GHOST_DRAIN_SPEED * delta, hp_ratio)
		else:
			health_ghost_ratio = hp_ratio

	var hp_ghost_mat := health_bar_ghost.material as ShaderMaterial
	hp_ghost_mat.set_shader_parameter("ratio", health_ghost_ratio)

	# --- Stamina ghost ---
	var stam_ratio := stamina / MAX_STAMINA
	if stamina_ghost_delay > 0.0:
		stamina_ghost_delay -= delta
	else:
		if stamina_ghost_ratio > stam_ratio:
			stamina_ghost_ratio = maxf(stamina_ghost_ratio - GHOST_DRAIN_SPEED * delta, stam_ratio)
		else:
			stamina_ghost_ratio = stam_ratio

	stam_ghost.size.x = STAM_BAR_W * stamina_ghost_ratio


func update_health_ui():
	var ratio := float(health) / float(max_health)
	var mat := health_bar_fill.material as ShaderMaterial
	mat.set_shader_parameter("ratio", ratio)
	health_ghost_delay = GHOST_DELAY


# ═══════════════════════════════════════════
#  UTILITY
# ═══════════════════════════════════════════

func _use_stamina(cost: float) -> bool:
	if stamina < cost:
		stamina_flash_timer = 0.2
		return false
	stamina -= cost
	stamina_ghost_delay = GHOST_DELAY
	stamina_regen_cooldown = STAMINA_REGEN_DELAY
	return true


func _trigger_shake(strength: float, duration: float):
	shake_strength = strength
	shake_timer = duration


func _trigger_hitstop(duration: float):
	hitstop_timer = duration


func play_anim(anim_name: String):
	if sprite.sprite_frames.has_animation(anim_name) and sprite.animation != anim_name:
		sprite.play(anim_name)


# ═══════════════════════════════════════════
#  ANIMATION CALLBACKS
# ═══════════════════════════════════════════

func _on_animation_finished():
	match sprite.animation:
		"Attack", "Attack2", "AttackCombo2hit", "CrouchAttack":
			combo_timer = COMBO_WINDOW
			_resolve_free_state()
		"Roll":
			if double_jump_rolling:
				double_jump_rolling = false
				sprite.speed_scale = 1.0
				_resolve_animation()
		"Dash":
			if state == State.DASH:
				_resolve_free_state()
		"WallClimbNoMovement":
			_finish_ledge_climb()
		"TurnAround":
			if turn_pending_dir != 0:
				facing_dir = turn_pending_dir
				turn_pending_dir = 0
			_resolve_animation()
			# Skip wind-up frames so run feels immediate out of a turn
			if sprite.animation == "Run":
				sprite.frame = 2
		"JumpFallInbetween":
			if state == State.FALL:
				play_anim("Fall")
		"Hit":
			pass  # hurt_timer handles transition
		"Death":
			pass


# ═══════════════════════════════════════════
#  CONTACT DAMAGE
# ═══════════════════════════════════════════

func _check_enemy_contact():
	if state == State.DEAD or is_invincible or state == State.DASH or state == State.ATTACK:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is CharacterBody2D and body.is_in_group("Enemy"):
			take_damage(1, body.global_position, body)
			return


# ═══════════════════════════════════════════
#  DAMAGE / DEATH
# ═══════════════════════════════════════════

func take_damage(amount := 1, from_pos := Vector2.ZERO, attacker: Node2D = null):
	if attacker != null and not is_instance_valid(attacker):
		attacker = null
	if state == State.DEAD or is_invincible or state == State.DASH:
		return

	# Parry check — if in parry window, reflect damage and cancel hit
	if attacker != null and _try_parry(attacker):
		return

	health -= amount
	update_health_ui()

	_disable_attack_hitbox()
	attack_hit_bodies.clear()
	if _is_grappling():
		_change_grapple_state(GrappleState.COOLDOWN)

	_change_state(State.HURT)

	_trigger_hitstop(HITSTOP_HURT)
	_trigger_shake(SHAKE_HURT_STRENGTH, SHAKE_HURT_DURATION)

	var kb_dir : float = signf(global_position.x - from_pos.x)
	if kb_dir == 0.0:
		kb_dir = float(-facing_dir)
	velocity = Vector2(kb_dir * KNOCKBACK_FORCE.x, KNOCKBACK_FORCE.y)

	is_invincible = true
	invincibility_timer = I_FRAMES

	stamina = maxf(stamina - 15.0, 0.0)
	stamina_regen_cooldown = STAMINA_REGEN_DELAY * 1.5

	if health <= 0:
		die()


func die():
	_change_state(State.DEAD)
	await sprite.animation_finished
	await get_tree().create_timer(0.5).timeout
	get_tree().reload_current_scene()
