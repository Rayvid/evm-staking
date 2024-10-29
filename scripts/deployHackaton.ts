import { ethers } from "hardhat";

async function main() {
  const ContractFactory = await ethers.getContractFactory("Hackaton");

  const contract = await ContractFactory.deploy();
  console.log("Contract deployed to address:", contract.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
