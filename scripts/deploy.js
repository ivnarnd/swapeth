const hre = require("hardhat");
async function main() {

  // 1. Desplegar PascalCoin
  const PascalCoin = await hre.ethers.getContractFactory("PascalCoin");
  const pascal = await PascalCoin.deploy();
  console.log("✅ PascalCoin desplegado en:", pascal.runner.address);

  // 2. Desplegar RobinCoin
  const RobinCoin = await hre.ethers.getContractFactory("RobinCoin");
  const robin = await RobinCoin.deploy();
  console.log("✅ RobinCoin desplegado en:", robin.runner.address);

  // 3. Desplegar SimpleSwap 
  const SimpleSwap = await hre.ethers.getContractFactory("SimpleSwap");
  const swap = await SimpleSwap.deploy();

  console.log("✅ SimpleSwap desplegado en:", swap.runner.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
