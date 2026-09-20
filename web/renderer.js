// Platform adapter only: Zig owns the camera, geometry, picking, and simulation.
export function createRenderer(canvas) {
  const gl = canvas.getContext("webgl", { antialias: true, alpha: false });
  if (!gl)
    throw new Error(
      "WebGL is unavailable. Enable hardware acceleration or use a WebGL-capable browser.",
    );
  function shader(type, source) {
    const result = gl.createShader(type);
    gl.shaderSource(result, source);
    gl.compileShader(result);
    if (!gl.getShaderParameter(result, gl.COMPILE_STATUS))
      throw new Error(gl.getShaderInfoLog(result));
    return result;
  }
  const program = gl.createProgram();
  gl.attachShader(
    program,
    shader(
      gl.VERTEX_SHADER,
      "attribute vec3 position; attribute vec3 color; varying vec3 tint; void main(){ gl_Position=vec4(position,1.0); tint=color; }",
    ),
  );
  gl.attachShader(
    program,
    shader(
      gl.FRAGMENT_SHADER,
      "precision mediump float; varying vec3 tint; void main(){gl_FragColor=vec4(tint,1.0);}",
    ),
  );
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS))
    throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  for (const [name, offset] of [
    ["position", 0],
    ["color", 12],
  ]) {
    const location = gl.getAttribLocation(program, name);
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, 3, gl.FLOAT, false, 24, offset);
  }
  gl.enable(gl.DEPTH_TEST);
  gl.depthFunc(gl.LEQUAL);
  gl.clearColor(0.773, 0.82, 0.753, 1);
  canvas.addEventListener("webglcontextlost", (event) => {
    event.preventDefault();
    document.getElementById("loading").hidden = false;
    document.getElementById("loading").textContent =
      "Graphics context lost. Refresh to restart the town.";
  });
  return {
    draw(vertices, count) {
      const ratio = Math.min(devicePixelRatio || 1, 2);
      const width = Math.round(canvas.clientWidth * ratio),
        height = Math.round(canvas.clientHeight * ratio);
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      gl.viewport(0, 0, width, height);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.DYNAMIC_DRAW);
      gl.drawArrays(gl.TRIANGLES, 0, count);
    },
  };
}
