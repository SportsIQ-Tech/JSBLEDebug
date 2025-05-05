import Foundation

struct Quaternion {
    var w: Double
    var x: Double
    var y: Double
    var z: Double
    
    init(w: Double = 1.0, x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }
    
    // Normalize the quaternion
    func normalized() -> Quaternion {
        let magnitude = sqrt(w*w + x*x + y*y + z*z)
        if magnitude > 0 {
            return Quaternion(
                w: w / magnitude,
                x: x / magnitude,
                y: y / magnitude,
                z: z / magnitude
            )
        }
        return Quaternion()
    }
} 