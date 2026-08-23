const hre = require("hardhat");

async function main() {

    const HealthcareDataExchange =
        await hre.ethers.getContractFactory(
            "HealthcareDataExchange"
        );

    const contract =
        await HealthcareDataExchange.deploy();

    await contract.waitForDeployment();

    console.log(
        "HealthcareDataExchange deployed to:",
        await contract.getAddress()
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});