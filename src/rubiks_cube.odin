package main

import "core:mem"
import "core:log"
import "core:math"

rubiks_cube_init :: proc() {
    for dim in 0..< SIZE {
        // TODO: fix calculation to center any cube

        mat := matrix[4,4]f32{
            1, 0, 0, -UNIT,
            0, 1, 0, -UNIT,
            0, 0, 1, -UNIT + UNIT * f32(dim),
            0, 0, 0, 1,
        }

        for row in 0..< SIZE {
            for col in 0..< SIZE {
                g_rubiks.cubes[dim * SIZE * SIZE + row * SIZE + col].model = mat
                mat[0, 3] += UNIT
            }

            mat[1, 3] += UNIT
            mat[0, 3] = -UNIT
        }
    }

    mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
    mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
}

cube_rotate :: proc(y: f32, x: f32, z: f32) -> matrix[4,4]f32 {
    B := matrix[4,4]f32{
        math.cos_f32(z), math.sin_f32(z), 0, 0,
        -math.sin_f32(z), math.cos_f32(z), 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }

    P := matrix[4,4]f32{
        1, 0, 0, 0,
        0, math.cos_f32(x), math.sin_f32(x), 0,
        0, -math.sin_f32(x), math.cos_f32(x), 0,
        0, 0, 0, 1,
    }

    H := matrix[4,4]f32{
        math.cos_f32(y), 0, -math.sin_f32(y), 0,
        0, 1, 0, 0,
        math.sin_f32(y), 0, math.cos_f32(y), 0,
        0, 0, 0, 1,
    }

    return B * P * H
}

rubiks_cube_turn_x :: proc(sides_to_turn: []int, is_turn_left: bool) {
    angle: f32 = 90.0

    if is_turn_left {
        angle = -90.0
    } 

    for dim in sides_to_turn {
        side := dim * SIZE * SIZE
        face: [SIZE * SIZE]matrix[4,4]f32

        for cube in 0..< SIZE * SIZE {
            face[cube] = cube_rotate(0, 0, math.to_radians_f32(angle)) * g_rubiks.cubes[side + cube].model 
        }

        for r in 0..<SIZE {
            for c in 0..<SIZE {
                if is_turn_left {
                    g_rubiks.cubes[side + c * SIZE + SIZE - r - 1].model = face[r * SIZE + c]
                } else {
                    g_rubiks.cubes[side + SIZE * SIZE - c * SIZE - SIZE + r].model = face[r * SIZE + c]
                }
            }
        }
    }
}

rubiks_cube_turn_y :: proc(sides_to_turn: []int, is_turn_down: bool) {
    angle: f32 = 90

    if is_turn_down {
        angle = -90
    }

    // 0, 1, 2

    // 
    for side in sides_to_turn {
        face: [SIZE * SIZE]matrix[4, 4]f32

        for d in 0..< SIZE {
            for r in 0..< SIZE {
                i := d * SIZE * SIZE + r * SIZE + side
                log.info(d * SIZE + r, i)
                face[d * SIZE + r] = cube_rotate(0, math.to_radians(angle), 0) * g_rubiks.cubes[i].model
            }
        }

        for i in 0..< SIZE {
        }

        

        // 0, 0, 0, -> 0, 0, 2,
        // 0, 1, 0, -> 0, 1, 1,
        // 0, 2, 0 ->  0, 2, 0


    }

}

animate_cube_turn :: proc(angles: ^[3]f32) {
    sides: [SIZE]int
    for i in 0..< SIZE { sides[i] = i }
    for i in 0..< len(angles) { angles[i] += g_animation.change[i] * ROTATION_SPEED }

    models: [CUBES]InstanceData

    for dim in sides {
        side := dim * SIZE * SIZE

        for cube in 0..< SIZE * SIZE {
            y, x, z := angles[0], angles[1], angles[2]
            yr, xr, zr := math.to_radians_f32(y), math.to_radians_f32(x), math.to_radians_f32(z)

            models[side + cube].highlight = g_rubiks.cubes[side + cube].highlight
            models[side + cube].model = cube_rotate(yr, xr, zr) * g_rubiks.cubes[side + cube].model
        }
    }

    mem.copy(g_cube_buf_maps[0], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))
    mem.copy(g_cube_buf_maps[1], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))

    for i in 0..< len(angles) {
        if math.abs(angles[i]) > math.abs(g_animation.angles[i]) {
            g_animate_turn = false
            angles[i] = 0
            g_animation.turn_proc(sides[:], g_animation.angles[i] < 0.0)
        }
    }
}
