// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HealthcareDataExchange
 * @notice Educational prototype for decentralized healthcare
 *         record metadata, consent and access management.
 *
 * IMPORTANT:
 * Never store real patient medical information on a public
 * blockchain using this contract.
 */
contract HealthcareDataExchange {

    // =========================================================
    // ENUMS
    // =========================================================

    enum Role {
        None,
        Patient,
        Doctor,
        Hospital,
        Admin
    }

    // =========================================================
    // STRUCTS
    // =========================================================

    struct User {
        address account;
        Role role;
        bool registered;
    }

    struct MedicalRecord {
        uint256 recordId;
        address patient;
        address createdBy;
        string recordType;
        bytes32 fileHash;
        string storageReference;
        uint256 timestamp;
        bool active;
    }

    struct Permission {
        bool allowed;
        uint256 expiry;
    }

    // =========================================================
    // STATE VARIABLES
    // =========================================================

    address public admin;

    uint256 private nextRecordId = 1;

    mapping(address => User) public users;

    mapping(uint256 => MedicalRecord) private records;

    mapping(address => uint256[]) private patientRecords;

    /*
     * recordId => doctor => permission
     */
    mapping(uint256 => mapping(address => Permission))
        private recordPermissions;

    // =========================================================
    // EVENTS
    // =========================================================

    event UserRegistered(
        address indexed account,
        Role role
    );

    event MedicalRecordAdded(
        uint256 indexed recordId,
        address indexed patient,
        address indexed createdBy,
        string recordType,
        bytes32 fileHash,
        string storageReference
    );

    event AccessGranted(
        uint256 indexed recordId,
        address indexed patient,
        address indexed doctor,
        uint256 expiry
    );

    event AccessRevoked(
        uint256 indexed recordId,
        address indexed patient,
        address indexed doctor
    );

    event RecordAccessed(
        uint256 indexed recordId,
        address indexed patient,
        address indexed accessor
    );

    // =========================================================
    // MODIFIERS
    // =========================================================

    modifier onlyAdmin() {
        require(
            msg.sender == admin,
            "Only admin can perform this action"
        );
        _;
    }

    modifier onlyPatient() {
        require(
            users[msg.sender].registered &&
            users[msg.sender].role == Role.Patient,
            "Only patient allowed"
        );
        _;
    }

    modifier onlyDoctor() {
        require(
            users[msg.sender].registered &&
            users[msg.sender].role == Role.Doctor,
            "Only doctor allowed"
        );
        _;
    }

    modifier onlyHospital() {
        require(
            users[msg.sender].registered &&
            users[msg.sender].role == Role.Hospital,
            "Only hospital allowed"
        );
        _;
    }

    modifier recordExists(uint256 recordId) {
        require(
            recordId > 0 &&
            recordId < nextRecordId,
            "Record does not exist"
        );
        _;
    }

    // =========================================================
    // CONSTRUCTOR
    // =========================================================

    constructor() {
        admin = msg.sender;

        users[msg.sender] = User({
            account: msg.sender,
            role: Role.Admin,
            registered: true
        });

        emit UserRegistered(
            msg.sender,
            Role.Admin
        );
    }

    // =========================================================
    // ROLE MANAGEMENT
    // =========================================================

    function registerUser(
        address account,
        Role role
    ) external onlyAdmin {

        require(
            account != address(0),
            "Invalid address"
        );

        require(
            role != Role.None &&
            role != Role.Admin,
            "Invalid role"
        );

        require(
            !users[account].registered,
            "User already registered"
        );

        users[account] = User({
            account: account,
            role: role,
            registered: true
        });

        emit UserRegistered(account, role);
    }

    function getRole(
        address account
    ) external view returns (Role) {

        return users[account].role;
    }

    // =========================================================
    // MEDICAL RECORD FUNCTIONS
    // =========================================================

    function addMedicalRecord(
        address patient,
        string calldata recordType,
        bytes32 fileHash,
        string calldata storageReference
    )
        external
        onlyHospital
        returns (uint256)
    {
        require(
            patient != address(0),
            "Invalid patient address"
        );

        require(
            users[patient].registered &&
            users[patient].role == Role.Patient,
            "Patient not registered"
        );

        require(
            fileHash != bytes32(0),
            "Invalid file hash"
        );

        require(
            bytes(recordType).length > 0,
            "Record type required"
        );

        uint256 recordId = nextRecordId;

        records[recordId] = MedicalRecord({
            recordId: recordId,
            patient: patient,
            createdBy: msg.sender,
            recordType: recordType,
            fileHash: fileHash,
            storageReference: storageReference,
            timestamp: block.timestamp,
            active: true
        });

        patientRecords[patient].push(recordId);

        nextRecordId++;

        emit MedicalRecordAdded(
            recordId,
            patient,
            msg.sender,
            recordType,
            fileHash,
            storageReference
        );

        return recordId;
    }

    // =========================================================
    // RECORD RETRIEVAL
    // =========================================================

    function getRecord(
        uint256 recordId
    )
        external
        recordExists(recordId)
        returns (MedicalRecord memory)
    {
        MedicalRecord memory record = records[recordId];

        require(
            record.active,
            "Record inactive"
        );

        bool authorized =
            msg.sender == record.patient ||
            hasAccessInternal(recordId, msg.sender);

        require(
            authorized,
            "Not authorized to access record"
        );

        emit RecordAccessed(
            recordId,
            record.patient,
            msg.sender
        );

        return record;
    }

    function getPatientRecords(
        address patient
    )
        external
        view
        returns (MedicalRecord[] memory)
    {
        require(
            msg.sender == patient ||
            (
                users[msg.sender].registered &&
                users[msg.sender].role == Role.Doctor
            ),
            "Not authorized"
        );

        uint256[] memory ids = patientRecords[patient];

        MedicalRecord[] memory result =
            new MedicalRecord[](ids.length);

        uint256 count = 0;

        for (uint256 i = 0; i < ids.length; i++) {

            uint256 id = ids[i];

            if (
                msg.sender == patient ||
                hasAccessInternal(id, msg.sender)
            ) {
                result[count] = records[id];
                count++;
            }
        }

        return result;
    }

    // =========================================================
    // CONSENT MANAGEMENT
    // =========================================================

    function grantAccess(
        uint256 recordId,
        address doctor,
        uint256 expiry
    )
        external
        onlyPatient
        recordExists(recordId)
    {
        MedicalRecord storage record =
            records[recordId];

        require(
            record.patient == msg.sender,
            "Not record owner"
        );

        require(
            doctor != address(0),
            "Invalid doctor address"
        );

        require(
            users[doctor].registered &&
            users[doctor].role == Role.Doctor,
            "Account is not a doctor"
        );

        require(
            expiry == 0 ||
            expiry > block.timestamp,
            "Invalid expiry"
        );

        recordPermissions[recordId][doctor] =
            Permission({
                allowed: true,
                expiry: expiry
            });

        emit AccessGranted(
            recordId,
            msg.sender,
            doctor,
            expiry
        );
    }

    function revokeAccess(
        uint256 recordId,
        address doctor
    )
        external
        onlyPatient
        recordExists(recordId)
    {
        MedicalRecord storage record =
            records[recordId];

        require(
            record.patient == msg.sender,
            "Not record owner"
        );

        require(
            doctor != address(0),
            "Invalid doctor"
        );

        recordPermissions[recordId][doctor].allowed =
            false;

        recordPermissions[recordId][doctor].expiry =
            0;

        emit AccessRevoked(
            recordId,
            msg.sender,
            doctor
        );
    }

    function hasAccess(
        uint256 recordId,
        address doctor
    )
        external
        view
        recordExists(recordId)
        returns (bool)
    {
        return hasAccessInternal(
            recordId,
            doctor
        );
    }

    function hasAccessInternal(
        uint256 recordId,
        address doctor
    )
        internal
        view
        returns (bool)
    {
        Permission memory permission =
            recordPermissions[recordId][doctor];

        if (!permission.allowed) {
            return false;
        }

        if (
            permission.expiry != 0 &&
            block.timestamp > permission.expiry
        ) {
            return false;
        }

        return true;
    }

    // =========================================================
    // PERMISSION INFORMATION
    // =========================================================

    function getPermission(
        uint256 recordId,
        address doctor
    )
        external
        view
        recordExists(recordId)
        returns (
            bool allowed,
            uint256 expiry
        )
    {
        Permission memory permission =
            recordPermissions[recordId][doctor];

        return (
            permission.allowed,
            permission.expiry
        );
    }

    // =========================================================
    // HELPER
    // =========================================================

    function getRecordCount()
        external
        view
        returns (uint256)
    {
        return nextRecordId - 1;
    }
}