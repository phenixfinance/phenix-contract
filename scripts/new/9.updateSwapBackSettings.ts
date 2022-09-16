import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const phenixTokenContract = await ethers.getContractAt("PhenixFinance", ca.phenixTokenAddress);

    console.log(`[ ------- Updating Swap Back Settings ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) ------- ]`);
    await phenixTokenContract.setSwapBackSettings(
        true,
        1,
        100000000
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
