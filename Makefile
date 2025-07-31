
SRC_DIR=src
SHADER_DIR=shaders
SHADER_CC=glslc

build: build_shaders
	odin build ${SRC_DIR} -out=orc

run: build_shaders
	odin run ${SRC_DIR} -out=orc

build_shaders:
	${SHADER_CC}  -fshader-stage=vert ${SHADER_DIR}/vert.glsl -o ${SRC_DIR}/vert.spv
	${SHADER_CC}  -fshader-stage=frag ${SHADER_DIR}/frag.glsl -o ${SRC_DIR}/frag.spv

