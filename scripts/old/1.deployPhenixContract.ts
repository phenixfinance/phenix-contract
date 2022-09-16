import { ethers } from "hardhat";

async function main() {
  const PhenixTokenContract = await ethers.getContractFactory("Phenix");
  const phenixTokenContract = await PhenixTokenContract.deploy();

  await phenixTokenContract.deployed();

  console.log(`Phenix Token Deployed to ${phenixTokenContract.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
