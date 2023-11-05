// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
// import hre from "hardhat";
const hre = require("hardhat");

async function main() {
  const erc20 = await hre.ethers.getContractFactory("MyERC20");

  const weth = await erc20.deploy("WETH", "WETH", 18);
  await weth.waitForDeployment();
  console.log("WETH deployed to:", await weth.getAddress());

  const usdc = await erc20.deploy("USDC", "USDC", 6);
  await usdc.waitForDeployment();
  console.log("USDC deployed to:", await usdc.getAddress());
  
  const marketplace = await hre.ethers.getContractFactory("Marketplace");
  const market = await marketplace.deploy(await weth.getAddress(), await usdc.getAddress());
  await market.waitForDeployment();
  console.log("Marketplace deployed to:", await market.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
