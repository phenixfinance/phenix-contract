import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const DATE_NOW = Math.floor(Date.now() / 1000);
    const phenixTokenContract = await ethers.getContractAt("PhenixFinance", ca.phenixTokenAddress);

    console.log(`[ ------- Rebasing ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) ------- ]`);
    await phenixTokenContract.rebaseAndSync();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
