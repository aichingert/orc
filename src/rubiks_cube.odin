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

rubiks_cube_turn_x :: proc(is_turn_left: bool) {
    angle: f32 = 90.0
    if is_turn_left {
        angle = -90.0
    } 

    for dim in 0..< SIZE {
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

rubiks_cube_turn_y :: proc(is_turn_down: bool) {
    angle: f32 = 90
    if is_turn_down {
        angle = -angle
    }

    for c in 0..< SIZE {
        if g_has_selection && !g_selection.is_row_selected && int(g_selection.col) != c {
            continue
        }

        face: [SIZE * SIZE]matrix[4, 4]f32

        for d in 0..< SIZE {
            for r in 0..< SIZE {
                i := d * SIZE * SIZE + r * SIZE + c
                face[d * SIZE + r] = cube_rotate(0, math.to_radians_f32(angle), 0) * g_rubiks.cubes[i].model
            }
        }

        for d in 0..<SIZE {
            for r in 0..<SIZE {
                index := 0

                if is_turn_down {
                    index = r * SIZE * SIZE + (SIZE - d - 1) * SIZE + c
                } else {
                    index = (SIZE - r - 1) * SIZE * SIZE + d * SIZE + c
                }

                g_rubiks.cubes[index].model = face[d * SIZE + r]
            }
        }
    }
}

rubiks_cube_turn_z :: proc(row: int, is_turn_left: bool) {
    angle: f32 = 90
    if is_turn_left {
        angle = -angle
    }

    rows: [SIZE * SIZE]matrix[4,4]f32

    for dim in 0..< SIZE {
        for col in 0..< SIZE {
            i := dim * SIZE * SIZE + row * SIZE + col
            rows[dim * SIZE + col] = cube_rotate(math.to_radians_f32(angle), 0, 0) * g_rubiks.cubes[i].model
        }
    }

    for dim in 0..< SIZE {
        for col in 0..< SIZE {
            index := 0

            if is_turn_left {
                index = (SIZE - col - 1) * SIZE * SIZE + row * SIZE + dim
            } else {
                index = col * SIZE * SIZE + row * SIZE + SIZE - dim - 1
            }

            g_rubiks.cubes[index].model = rows[dim * SIZE + col]
        }
    }

}

rubiks_cube_turn_selection :: proc(angles: ^[3]f32) {
    if g_selection.is_row_selected {
        if angles[2] == 0.0 {
            g_animate_turn = false
            angles^ = {0, 0, 0}
            return 
        }

        models: [CUBES]InstanceData
        for cube in 0..< CUBES { models[cube] = g_rubiks.cubes[cube] }

        for dim in 0..< SIZE {
            for col in 0..< SIZE {
                // TODO
                i := dim * SIZE * SIZE + int(g_selection.row) * SIZE + col
                models[i].model = cube_rotate(math.to_radians_f32(angles[2]), 0, 0) * models[i].model
            }
        }
        mem.copy(g_cube_buf_maps[0], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))
        mem.copy(g_cube_buf_maps[1], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))

        if math.abs(angles[2]) > math.abs(g_animation.angles[2]) {
            g_animate_turn = false
            angles^ = {0, 0, 0}
            rubiks_cube_turn_z(int(g_selection.row), g_animation.angles[2] < 0)
            mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
            mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
        }
        
        return
    }

    if angles[1] == 0.0 {
        g_animate_turn = false
        angles^ = {0, 0, 0}
        return 
    }

    models: [CUBES]InstanceData
    for cube in 0..< CUBES { models[cube] = g_rubiks.cubes[cube] }

    for dim in 0..< SIZE {
        for row in 0..< SIZE {
            i := dim * SIZE * SIZE + row * SIZE + int(g_selection.col)
            models[i].model = cube_rotate(0, math.to_radians_f32(angles[1]), 0) * models[i].model
        }
    }

    mem.copy(g_cube_buf_maps[0], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))
    mem.copy(g_cube_buf_maps[1], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))

    if math.abs(angles[1]) > math.abs(g_animation.angles[1]) {
        g_animate_turn = false
        angles^ = {0, 0, 0}
        rubiks_cube_turn_y(g_animation.angles[1] < 0)
        mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
        mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
    } 
}

animate_cube_turn :: proc(angles: ^[3]f32) {
    for i in 0..< len(angles) { angles[i] += g_animation.change[i] * ROTATION_SPEED }

    if g_has_selection {
        rubiks_cube_turn_selection(angles)
        return
    }

    y, x, z := angles[0], angles[1], angles[2]
    yr, xr, zr := math.to_radians_f32(y), math.to_radians_f32(x), math.to_radians_f32(z)
    models: [CUBES]InstanceData

    for cube in 0..< CUBES {
        models[cube] = g_rubiks.cubes[cube]
        models[cube].model = cube_rotate(yr, xr, zr) * models[cube].model
    }

    mem.copy(g_cube_buf_maps[0], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))
    mem.copy(g_cube_buf_maps[1], raw_data(&models), CUBES * size_of(g_rubiks.cubes[0]))

    for i in 0..< len(angles) {
        if math.abs(angles[i]) > math.abs(g_animation.angles[i]) {
            g_animate_turn = false
            g_animation.turn_proc(g_animation.angles[i] < 0.0)
            angles^ = {0, 0, 0}

            mem.copy(g_cube_buf_maps[0], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
            mem.copy(g_cube_buf_maps[1], raw_data(g_rubiks.cubes), CUBES * size_of(g_rubiks.cubes[0]))
        }
    }
}

rubiks_cube_set_selection :: proc(value: f32) {
    if g_selection.is_row_selected {
        for dim in 0..< SIZE {
            for col in 0..<SIZE {
                g_rubiks.cubes[dim * SIZE * SIZE + int(g_selection.row) * SIZE + col].highlight = value
            }
        }
        return
    }

    for dim in 0..< SIZE {
        for row in 0..<SIZE {
            g_rubiks.cubes[dim * SIZE * SIZE + row * SIZE + int(g_selection.col)].highlight = value
        }
    }
}

