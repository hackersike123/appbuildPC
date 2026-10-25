(() => {
  const warning = document.getElementById('warning');

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x111111);
  const camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 0.1, 1000);
  camera.position.set(0, 100, 300);
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  document.body.appendChild(renderer.domElement);

  // Light
  const light = new THREE.DirectionalLight(0xffffff, 1);
  light.position.set(100, 200, 100);
  scene.add(light);
  scene.add(new THREE.AmbientLight(0x404040));

  // Case dimensions (mm scaled down)
  const caseDims = { width: 200, height: 400, depth: 450 };
  const caseGeom = new THREE.BoxGeometry(caseDims.width, caseDims.height, caseDims.depth);
  const caseMat = new THREE.MeshBasicMaterial({ color: 0x888888, wireframe: true, opacity: 0.5, transparent: true });
  const caseMesh = new THREE.Mesh(caseGeom, caseMat);
  scene.add(caseMesh);

  // Mainboard (flat PCB)
  const board = new THREE.Mesh(
    new THREE.BoxGeometry(180, 2, 300),
    new THREE.MeshStandardMaterial({ color: 0x00aa00 })
  );
  board.position.set(0, -caseDims.height / 2 + 3, 0);
  scene.add(board);

  // CPU (small box on board)
  const cpu = new THREE.Mesh(
    new THREE.BoxGeometry(30, 10, 30),
    new THREE.MeshStandardMaterial({ color: 0xffaa00 })
  );
  cpu.position.set(-50, -caseDims.height / 2 + 8, -100);
  scene.add(cpu);

  // GPU (long card)
  const gpu = new THREE.Mesh(
    new THREE.BoxGeometry(20, 5, 250),
    new THREE.MeshStandardMaterial({ color: 0x0000ff })
  );
  gpu.position.set(60, -caseDims.height / 2 + 7, 0);
  scene.add(gpu);

  // Simple collision check: GPU length vs case depth
  const gpuHalfDepth = 250 / 2;
  const caseHalfDepth = caseDims.depth / 2;
  if (Math.abs(gpu.position.z) + gpuHalfDepth > caseHalfDepth) {
    warning.textContent = 'Cảnh báo: GPU quá dài, vượt qua không gian case.';
  }

  // Resize handling
  window.addEventListener('resize', () => {
    const w = window.innerWidth, h = window.innerHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  });

  function animate() {
    requestAnimationFrame(animate);
    renderer.render(scene, camera);
  }
  animate();
})();
