using Godot;

public partial class Camerapivot : Node3D
{
	[Export] public float MouseSensitivity = 0.0025f;
	[Export] public float MinPitch = -40.0f;
	[Export] public float MaxPitch = 20.0f;

	private float _yaw = 0.0f;
	private float _pitch = 0.0f;
	private bool _lookingBack = false;

	public override void _Ready()
	{
		Input.MouseMode = Input.MouseModeEnum.Captured;
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is InputEventMouseMotion mouseMotion)
		{
			// LEFT / RIGHT = unlimited 360° orbit
			_yaw -= mouseMotion.Relative.X * MouseSensitivity;

			// UP / DOWN = limited
			_pitch -= mouseMotion.Relative.Y * MouseSensitivity;

			_pitch = Mathf.Clamp(
				_pitch,
				Mathf.DegToRad(MinPitch),
				Mathf.DegToRad(MaxPitch)
			);
		}

		if (@event.IsActionPressed("look_back"))
		{
			_lookingBack = true;
		}

		if (@event.IsActionReleased("look_back"))
		{
			_lookingBack = false;
		}

		if (@event.IsActionPressed("ui_cancel"))
		{
			Input.MouseMode =
				Input.MouseMode == Input.MouseModeEnum.Captured
					? Input.MouseModeEnum.Visible
					: Input.MouseModeEnum.Captured;
		}
	}

	public override void _Process(double delta)
	{
		float targetYaw = _lookingBack
			? _yaw + Mathf.Pi
			: _yaw;

		Rotation = new Vector3(
			_pitch,
			targetYaw,
			0.0f
		);
	}
}
