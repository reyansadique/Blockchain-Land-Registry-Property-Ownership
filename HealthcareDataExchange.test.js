const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HealthcareDataExchange", function () {

    let contract;

    let admin;
    let patient;
    let doctor;
    let hospital;
    let attacker;

    const ROLE_PATIENT = 1;
    const ROLE_DOCTOR = 2;
    const ROLE_HOSPITAL = 3;

    const fileHash =
        ethers.keccak256(
            ethers.toUtf8Bytes(
                "synthetic-medical-record-001"
            )
        );

    beforeEach(async function () {

        [
            admin,
            patient,
            doctor,
            hospital,
            attacker
        ] = await ethers.getSigners();

        const Factory =
            await ethers.getContractFactory(
                "HealthcareDataExchange"
            );

        contract = await Factory.deploy();

        await contract.waitForDeployment();

        // Register patient
        await contract.registerUser(
            patient.address,
            ROLE_PATIENT
        );

        // Register doctor
        await contract.registerUser(
            doctor.address,
            ROLE_DOCTOR
        );

        // Register hospital
        await contract.registerUser(
            hospital.address,
            ROLE_HOSPITAL
        );
    });

    // =====================================================
    // ROLE TESTS
    // =====================================================

    it("should register patient", async function () {

        expect(
            await contract.getRole(patient.address)
        ).to.equal(ROLE_PATIENT);
    });

    it("should register doctor", async function () {

        expect(
            await contract.getRole(doctor.address)
        ).to.equal(ROLE_DOCTOR);
    });

    it("should register hospital", async function () {

        expect(
            await contract.getRole(hospital.address)
        ).to.equal(ROLE_HOSPITAL);
    });

    it("should reject unauthorized registration", async function () {

        await expect(
            contract
                .connect(attacker)
                .registerUser(
                    attacker.address,
                    ROLE_DOCTOR
                )
        ).to.be.revertedWith(
            "Only admin can perform this action"
        );
    });

    // =====================================================
    // RECORD TESTS
    // =====================================================

    it("hospital should add patient record", async function () {

        await expect(
            contract
                .connect(hospital)
                .addMedicalRecord(
                    patient.address,
                    "Lab Report",
                    fileHash,
                    "local://medical_record_001.json"
                )
        )
            .to.emit(
                contract,
                "MedicalRecordAdded"
            );

        expect(
            await contract.getRecordCount()
        ).to.equal(1);
    });

    it("should reject invalid patient", async function () {

        await expect(
            contract
                .connect(hospital)
                .addMedicalRecord(
                    ethers.ZeroAddress,
                    "Lab Report",
                    fileHash,
                    "local://record.json"
                )
        ).to.be.revertedWith(
            "Invalid patient address"
        );
    });

    it("should reject unauthorized record creation", async function () {

        await expect(
            contract
                .connect(attacker)
                .addMedicalRecord(
                    patient.address,
                    "Lab Report",
                    fileHash,
                    "local://record.json"
                )
        ).to.be.revertedWith(
            "Only hospital allowed"
        );
    });

    // =====================================================
    // ACCESS TESTS
    // =====================================================

    async function createRecord() {

        await contract
            .connect(hospital)
            .addMedicalRecord(
                patient.address,
                "Lab Report",
                fileHash,
                "local://medical_record_001.json"
            );
    }

    it("doctor should not access without permission", async function () {

        await createRecord();

        await expect(
            contract
                .connect(doctor)
                .getRecord(1)
        ).to.be.revertedWith(
            "Not authorized to access record"
        );
    });

    it("patient should grant doctor access", async function () {

        await createRecord();

        await expect(
            contract
                .connect(patient)
                .grantAccess(
                    1,
                    doctor.address,
                    0
                )
        )
            .to.emit(
                contract,
                "AccessGranted"
            );

        expect(
            await contract.hasAccess(
                1,
                doctor.address
            )
        ).to.equal(true);
    });

    it("authorized doctor should access record", async function () {

        await createRecord();

        await contract
            .connect(patient)
            .grantAccess(
                1,
                doctor.address,
                0
            );

        const record =
            await contract
                .connect(doctor)
                .getRecord(1);

        expect(record.recordId).to.equal(1);
        expect(record.patient)
            .to.equal(patient.address);
        expect(record.recordType)
            .to.equal("Lab Report");
        expect(record.fileHash)
            .to.equal(fileHash);
    });

    it("patient should revoke doctor access", async function () {

        await createRecord();

        await contract
            .connect(patient)
            .grantAccess(
                1,
                doctor.address,
                0
            );

        await expect(
            contract
                .connect(patient)
                .revokeAccess(
                    1,
                    doctor.address
                )
        )
            .to.emit(
                contract,
                "AccessRevoked"
            );

        expect(
            await contract.hasAccess(
                1,
                doctor.address
            )
        ).to.equal(false);
    });

    it("doctor should fail after revocation", async function () {

        await createRecord();

        await contract
            .connect(patient)
            .grantAccess(
                1,
                doctor.address,
                0
            );

        await contract
            .connect(patient)
            .revokeAccess(
                1,
                doctor.address
            );

        await expect(
            contract
                .connect(doctor)
                .getRecord(1)
        ).to.be.revertedWith(
            "Not authorized to access record"
        );
    });

    // =====================================================
    // HASH TEST
    // =====================================================

    it("record hash should remain unchanged", async function () {

        await createRecord();

        const record =
            await contract
                .connect(patient)
                .getRecord(1);

        expect(record.fileHash)
            .to.equal(fileHash);
    });

    // =====================================================
    // EVENT TEST
    // =====================================================

    it("should emit UserRegistered", async function () {

        const newPatient =
            (await ethers.getSigners())[5];

        await expect(
            contract.registerUser(
                newPatient.address,
                ROLE_PATIENT
            )
        )
            .to.emit(
                contract,
                "UserRegistered"
            )
            .withArgs(
                newPatient.address,
                ROLE_PATIENT
            );
    });

    // =====================================================
    // INVALID RECORD
    // =====================================================

    it("should reject invalid record ID", async function () {

        await expect(
            contract
                .connect(patient)
                .getRecord(999)
        ).to.be.revertedWith(
            "Record does not exist"
        );
    });

    // =====================================================
    // EXPIRY TEST
    // =====================================================

    it("should support permission expiry", async function () {

        await createRecord();

        const latestBlock =
            await ethers.provider.getBlock(
                "latest"
            );

        const expiry =
            latestBlock.timestamp + 3600;

        await contract
            .connect(patient)
            .grantAccess(
                1,
                doctor.address,
                expiry
            );

        expect(
            await contract.hasAccess(
                1,
                doctor.address
            )
        ).to.equal(true);
    });
});