var ProcessBuilder = Java.type('java.lang.ProcessBuilder');
var pb = new ProcessBuilder('bash', 'scripts/maestro/memory-pressure.sh');
pb.inheritIO();
var process = pb.start();
if (process.waitFor() !== 0) {
  throw new Error('memory-pressure.sh failed');
}