import { createWorkbenchServer } from './server.js';

const server = createWorkbenchServer({ host: process.env.MORPHIR_WORKBENCH_HOST_URL });
server.listen(Number(process.env.MORPHIR_WORKBENCH_PORT ?? 5173), '127.0.0.1', () => {
  console.log(`Morphir Workbench: http://127.0.0.1:${server.address().port}`);
});
