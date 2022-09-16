import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const DATE_NOW = Math.floor(Date.now() / 1000);
    const phenixTokenContract = await ethers.getContractAt("Phenix", ca.phenixTokenAddress);
    
    console.log(`[ ------- ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) Contract Information] ------- ]`);
    console.log(`[ > ] Address:`, phenixTokenContract.address);
    console.log(`[ > ] Router Address:`, await phenixTokenContract.router());
    console.log(`[ > ] Pair Address:`, await phenixTokenContract.pair());
    console.log(`[ > ] Owner Address:`, await phenixTokenContract.owner());
    console.log(`[ > ] Total Supply:`, ethers.utils.commify(ethers.utils.formatEther(await phenixTokenContract.totalSupply())), await phenixTokenContract.symbol());
    console.log(`[ > ] Since Last Rebase:`, DATE_NOW - parseInt(await (await phenixTokenContract.lastRebaseTimestamp()).toString()), 'seconds');
    console.log(`[ > ] Last Rebase Delta:`, ethers.utils.commify(ethers.utils.formatEther(await phenixTokenContract.lastRebaseDelta())), await phenixTokenContract.symbol());
    // console.log(`[ > ] Next Rebase Delta:`, ethers.utils.commify(ethers.utils.formatEther(await phenixTokenContract.getNextRebase(DATE_NOW))), await phenixTokenContract.symbol());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
