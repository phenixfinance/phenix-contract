import { ethers } from "hardhat";
import ca from "./contractAddresses";

async function main() {
    const FXP_BASE = 1000000;
    const DATE_NOW = Math.floor(Date.now() / 1000);
    const phenixTokenContract = await ethers.getContractAt("PhenixFinance", ca.phenixTokenAddress);
    
    console.log(`[ ------- ${await phenixTokenContract.name()} (${await phenixTokenContract.symbol()}) Contract Information] ------- ]`);
    console.log(`[ > ] Address:`, phenixTokenContract.address);
    console.log(`[ > ] Router Address:`, await phenixTokenContract.router());
    console.log(`[ > ] Pair Address:`, await phenixTokenContract.pairAddresses(0));
    console.log(`[ > ] Owner Address:`, await phenixTokenContract.owner());
    console.log(`[ > ] Total Supply:`, ethers.utils.commify(ethers.utils.formatEther(await phenixTokenContract.totalSupply())), await phenixTokenContract.symbol());
    console.log(`[ > ] Since Last Rebase:`, DATE_NOW - parseInt(await (await phenixTokenContract.lastRebaseTimestamp()).toString()), 'seconds');
    console.log(`[ > ] Last Rebase Delta:`, ethers.utils.commify(ethers.utils.formatEther(await phenixTokenContract.lastRebaseDelta())), await phenixTokenContract.symbol());

    const nextRebase = parseInt(ethers.utils.formatEther(await phenixTokenContract.getNextRebase(DATE_NOW)));
    const nextRebaseDay = parseInt(ethers.utils.formatEther(await phenixTokenContract.getNextRebase(DATE_NOW + 86400))) - nextRebase;

    console.log(`[ > ] Next Rebase Delta:`, ethers.utils.commify(nextRebase), await phenixTokenContract.symbol());
    console.log(`[ > ] Rebase Delta (1 Day):`, ethers.utils.commify(nextRebaseDay), await phenixTokenContract.symbol());

    const rx3Multiplier = (parseFloat(await (await phenixTokenContract.rebaseRX3Multiplier()).toString()) - FXP_BASE) / FXP_BASE * 100;
    const rx3MultiplierMax = (parseFloat(await (await phenixTokenContract.rebaseMaxRX3Multiplier()).toString()) - FXP_BASE) / FXP_BASE * 100;
    const rx3MultiplierStep = parseFloat(await (await phenixTokenContract.rebaseRX3MultiplierStep()).toString()) / FXP_BASE * 100;


    console.log(`[ > ] RX3 Multiplier (%):`, rx3Multiplier, "%");
    console.log(`[ > ] RX3 Multiplier Step (%):`, rx3MultiplierStep, "%")
    console.log(`[ > ] RX3 Multiplier Max (%):`, rx3MultiplierMax, "%")
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
