using Godot;
using System;

public partial class CameraPivot : Node3D
{
	[Export] public float MouseSensitivity=0.003f;
	[Export] public float MinY=-15.0f;
	[Export] public float MaxY=15.0f;
	private bool _lookback=false;
	private float _yaw=0.0f;
	private float _pitch=0.0f;
	private Camera3D _camera;
	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		_camera=GetNode<Camera3D>("car_cam");
		Input.MouseMode=Input.MouseModeEnum.Captured;
	}
	public override void _UnhandledInput(InputEvent @event)
	{
		if(@event is InputEventMouseMotion mouse)
		{
			_yaw-=mouse.Relative.X*MouseSensitivity;
			_pitch-=mouse.Relative.Y*MouseSensitivity;
			_pitch=Mathf.Clamp(
				_pitch,
				Mathf.DegToRad(MinY),
				Mathf.DegToRad(MaxY)
			);	
		}
		if(@event.IsActionPressed("look_back"))
		{
			_lookback=true;	
		}
		if(@event.IsActionReleased("look_back"))
		{
			_lookback=false;
		}
		if(@event.IsActionPressed("ui_cancel"))
		{
			GetTree().Quit();
		}
	}
	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		float final_yaw=_yaw;
		if(_lookback)
		{
			final_yaw+=Mathf.Pi;
		}
		Rotation =new Vector3(
			0.0f,
			final_yaw,
			0.0f
		);
		_camera.Rotation=new Vector3(_pitch,0.0f,0.0f);
	}
}
