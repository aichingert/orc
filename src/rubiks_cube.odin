package main

import "core:math"
import "core:mem"

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

rubiks_cube_turn_x :: proc(sides_to_turn: []int, is_left_turn: bool) {
    angle: f32 = 90.0

    if is_left_turn {
        angle = -90.0
    } 

    for dim in sides_to_turn {
        side := dim * SIZE * SIZE
        face := [SIZE * SIZE]matrix[4,4]f32{}

        for cube in 0..< SIZE * SIZE {
            face[cube] = g_rubiks.cubes[side + cube].model
        }

        for r in 0..<SIZE {
            for c in 0..<SIZE {
                if is_left_turn {
                    g_rubiks.cubes[dim * SIZE * SIZE + c * SIZE + SIZE - r - 1].model = face[r * SIZE + c]
                } else {
                    g_rubiks.cubes[dim * SIZE * SIZE + SIZE * SIZE - c * SIZE - SIZE + r].model = face[r * SIZE + c]
                }
            }
        }
    }
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

animate_cube_turn :: proc(angles: ^[3]f32) {
    sides: [SIZE]int
    for i in 0..< SIZE { sides[i] = i }
    for i in 0..< len(angles) { angles[i] += g_animation.change[i] * ROTATION_SPEED }

    for dim in sides {
        side := dim * SIZE * SIZE

        for cube in 0..< SIZE * SIZE {
            y, x, z := g_animation.change[0], g_animation.change[1], g_animation.change[2]
            ys, xs, zs := y * ROTATION_SPEED, x * ROTATION_SPEED, z * ROTATION_SPEED
            yr, xr, zr := math.to_radians_f32(ys), math.to_radians_f32(xs), math.to_radians_f32(zs)

            g_rubiks.cubes[side + cube].model = cube_rotate(yr, xr, zr) * g_rubiks.cubes[side + cube].model
        }
    }

    mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
    mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))

    if math.abs(angles[2]) > math.abs(g_animation.angles[2]) {
        g_animate_turn = false
        angles[2] = 0
        rubiks_cube_turn_x(sides[:], g_animation.angles[2] < 0.0)
    }
    if math.abs(angles[1]) > math.abs(g_animation.angles[1]) {
        g_animate_turn = false
        angles[1] = 0
        //TODO: rubiks_cube_turn_y(sides, g_animation.angles[1] < 0.0)
    }

}
