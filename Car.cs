using Godot;

public partial class Car : VehicleBody3D
{
	// =========================
	// WHEELS (Matches your Scene Tree)
	// =========================
	[Export] public VehicleWheel3D fl;
	[Export] public VehicleWheel3D fr;
	[Export] public VehicleWheel3D rl;
	[Export] public VehicleWheel3D rr;

	// =========================
	// VEHICLE SETTINGS
	// =========================
	[Export] public float SteeringLimit = 0.4f;
	[Export] public float SteeringSpeed = 5.0f;
	[Export] public float MaxEngineForce = 200.0f; 
	[Export] public float MaxBrakeForce = 50.0f;

	[Export] public bool DebugPrint = true;
	private float currentSteering = 0.0f;

	public override void _Ready()
	{
		if (fl == null) GD.PrintErr("FL wheel is NOT assigned.");
		if (fr == null) GD.PrintErr("FR wheel is NOT assigned.");
		if (rl == null) GD.PrintErr("RL wheel is NOT assigned.");
		if (rr == null) GD.PrintErr("RR wheel is NOT assigned.");
		
		GD.Print("Vehicle script loaded.");
	}

	public override void _PhysicsProcess(double delta)
	{
		float dt = (float)delta;

		// =====================================================
		// 1. STEERING (Front Wheels)
		// =====================================================
		float steeringInput = Input.GetAxis("right", "left");
		float targetSteering = steeringInput * SteeringLimit;
		
		currentSteering = Mathf.Lerp(currentSteering, targetSteering, SteeringSpeed * dt);

		if (fl != null) fl.Steering = currentSteering;
		if (fr != null) fr.Steering = currentSteering;

		// =====================================================
		// 2. ACCELERATION (Rear Wheels)
		// =====================================================
		float throttle = Input.GetAxis("backward", "forward");
		float engineForce = throttle * MaxEngineForce;

		if (rl != null) rl.EngineForce = engineForce;
		if (rr != null) rr.EngineForce = engineForce;

		// =====================================================
		// 3. BRAKING (All Wheels)
		// =====================================================
		float brakeForce = Input.IsActionPressed("hand_brake") ? MaxBrakeForce : 0.0f;

		if (fl != null) fl.Brake = brakeForce;
		if (fr != null) fr.Brake = brakeForce;
		if (rl != null) rl.Brake = brakeForce;
		if (rr != null) rr.Brake = brakeForce;

		// =====================================================
		// 4. DEBUG OUTPUT
		// =====================================================
		if (DebugPrint)
		{
			bool rlContact = rl != null && rl.IsInContact();
			bool rrContact = rr != null && rr.IsInContact();
			
			GD.Print($"Throttle: {throttle} | Force: {engineForce} | Steer: {currentSteering:F2} | RL Contact: {rlContact} | RR Contact: {rrContact}");
		}
	}
}
