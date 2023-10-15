// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./helpers/EmailWalletCoreTestHelper.sol";
import "./mocks/TestNFTExtension.sol";

contract UnclaimedStateTest is EmailWalletCoreTestHelper {
    address testExtensionAddr;
    TestNFTExtension ext;
    DummyApes dummyApes;
    string[][] public templates = new string[][](1);

    function setUp() public override {
        super.setUp();
        _registerRelayer();
        _registerAndInitializeAccount();

        // Publish and install extension
        ext = new TestNFTExtension(address(core));
        testExtensionAddr = address(ext);
        dummyApes = DummyApes(ext.addressOfNFTName("APE"));

        templates[0] = ["NFT", "Send", "{uint}", "of", "{string}", "to", "{recipient}"];
        core.publishExtension("NFT Wallet", testExtensionAddr, templates, 0.1 ether);

        EmailOp memory emailOp = _getBaseEmailOp();
        emailOp.command = Commands.INSTALL_EXTENSION;
        emailOp.extManagerParams.extensionName = "NFT Wallet";
        emailOp.maskedSubject = "Install extension NFT Wallet";
        emailOp.emailNullifier = bytes32(uint256(93845));

        vm.startPrank(relayer);
        core.handleEmailOp(emailOp);
        vm.stopPrank();
    }

    function test_RegisterUnclaimedState_FromEmailOp() public {
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

        EmailOp memory emailOp = _getBaseEmailOp();
        emailOp.command = "NFT";
        emailOp.maskedSubject = string.concat("NFT Send 55 of APE to ");
        emailOp.extensionParams.subjectTemplateIndex = 0;
        emailOp.hasEmailRecipient = true;
        emailOp.recipientEmailAddrCommit = recipientEmailAddrCommit;
        emailOp.extensionParams.subjectParams = new bytes[](2);
        emailOp.extensionParams.subjectParams[0] = abi.encode(55);
        emailOp.extensionParams.subjectParams[1] = abi.encode("APE");

        bytes memory expectedState = abi.encode("(address,uint256)", address(dummyApes), 55);

        vm.startPrank(walletAddr);
        dummyApes.freeMint(walletAddr, 55); // Mint a NFT with tokenId 55 to walletAddr
        vm.stopPrank();

        vm.deal(relayer, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(relayer);
        vm.expectEmit();
        emit UnclaimedStateRegistered(
            recipientEmailAddrCommit,
            testExtensionAddr,
            walletAddr,
            block.timestamp + unclaimedFundExpirationDuration, // should be the default expiration time
            expectedState,
            0, // dont announce randomness and email
            ""
        );
        core.handleEmailOp{value: unclaimedStateClaimGas * maxFeePerGas}(emailOp);
        vm.stopPrank();

        (bytes32 emailAddrCommit, address extensionAddr, address sender, bytes memory state, uint256 expiryTime) = core
            .unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);

        assertEq(emailAddrCommit, recipientEmailAddrCommit, "emailAddrCommit mismatch");
        assertEq(extensionAddr, testExtensionAddr, "extensionAddr mismatch");
        assertEq(sender, walletAddr, "sender mismatch");
        assertEq(state, expectedState, "state mismatch");
        assertEq(expiryTime, block.timestamp + unclaimedFundExpirationDuration, "expiryTime mismatch");
    }

    function test_RevertIf_ExtensionDontRegisterUnclaimedFunds_FromEmailOp() public {
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

        EmailOp memory emailOp = _getBaseEmailOp();
        emailOp.command = "NFT";
        emailOp.maskedSubject = string.concat("NFT Send 55 of APE to ");
        emailOp.extensionParams.subjectTemplateIndex = 0;
        emailOp.hasEmailRecipient = true;
        emailOp.recipientEmailAddrCommit = recipientEmailAddrCommit;
        emailOp.extensionParams.subjectParams = new bytes[](2);
        emailOp.extensionParams.subjectParams[0] = abi.encode(55);
        emailOp.extensionParams.subjectParams[1] = abi.encode("APE");

        vm.deal(relayer, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(relayer);
        (bool success, bytes memory reason) = core.handleEmailOp{value: unclaimedStateClaimGas * maxFeePerGas}(emailOp);
        vm.stopPrank();

        assertEq(success, false, "handleEmailOp should fail");
        assertEq(reason, "unclaimed state registration failed", "reason mismatch");
    }

    function test_RevertIf_UnclaimedStateExists_Internal() public {
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

        EmailOp memory emailOp = _getBaseEmailOp();
        emailOp.command = "NFT";
        emailOp.maskedSubject = string.concat("NFT Send 55 of APE to ");
        emailOp.extensionParams.subjectTemplateIndex = 0;
        emailOp.hasEmailRecipient = true;
        emailOp.recipientEmailAddrCommit = recipientEmailAddrCommit;
        emailOp.extensionParams.subjectParams = new bytes[](2);
        emailOp.extensionParams.subjectParams[0] = abi.encode(55);
        emailOp.extensionParams.subjectParams[1] = abi.encode("APE");

        EmailOp memory emailOp2 = _getBaseEmailOp();
        emailOp2.command = "NFT";
        emailOp2.maskedSubject = string.concat("NFT Send 22 of APE to ");
        emailOp2.extensionParams.subjectTemplateIndex = 0;
        emailOp2.hasEmailRecipient = true;
        emailOp2.recipientEmailAddrCommit = recipientEmailAddrCommit; // Use same emailAddrCommit
        emailOp2.extensionParams.subjectParams = new bytes[](2);
        emailOp2.extensionParams.subjectParams[0] = abi.encode(55);
        emailOp2.extensionParams.subjectParams[1] = abi.encode("APE");
        emailOp2.emailNullifier = bytes32(uint256(93845));

        vm.startPrank(walletAddr);
        dummyApes.freeMint(walletAddr, 55);
        dummyApes.freeMint(walletAddr, 22);
        vm.stopPrank();

        vm.deal(relayer, 2 * unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(relayer);
        core.handleEmailOp{value: unclaimedStateClaimGas * maxFeePerGas}(emailOp);
        (bool success, bytes memory reason) = core.handleEmailOp{value: unclaimedStateClaimGas * maxFeePerGas}(
            emailOp2
        );
        vm.stopPrank();

        assertEq(success, false, "handleEmailOp should fail");
        assertEq(reason, "unclaimed state exists", "reason mismatch");
    }

    function test_RevertWhen_MultipleUnclaimedRegistered() public {
        // vm.startPrank(testExtensionAddr);
        // core.registerUnclaimedStateAsExtension
    }

    function test_RegisterUnclaimedState_External() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        vm.expectEmit();
        emit UnclaimedStateRegistered(
            recipientEmailAddrCommit,
            testExtensionAddr,
            walletAddr,
            block.timestamp + unclaimedFundExpirationDuration, // should be the default expiration time
            state,
            0, // dont announce randomness and email
            ""
        );
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            0,
            ""
        );
        vm.stopPrank();

        (
            bytes32 emailAddrCommit,
            address extensionAddr,
            address ufSender,
            bytes memory usState,
            uint256 expiryTime
        ) = core.unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);

        assertEq(emailAddrCommit, recipientEmailAddrCommit, "emailAddrCommit mismatch");
        assertEq(extensionAddr, testExtensionAddr, "extensionAddr mismatch");
        assertEq(sender, ufSender, "sender mismatch");
        assertEq(usState, state, "state mismatch");
        assertEq(expiryTime, block.timestamp + unclaimedFundExpirationDuration, "expiryTime mismatch");
    }

    function test_RegisterUnclaimedState_ExternalWithCustomExpiry() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);
        uint256 expiryTime = block.timestamp + 1000;

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            expiryTime,
            0,
            ""
        );
        vm.stopPrank();

        (, , , , uint256 usExpiry) = core.unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);

        assertEq(expiryTime, usExpiry, "expiryTime mismatch");
    }

    function test_RegisterUnclaimedState_ExternalWithAnnouncement() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);
        string memory emailAddr = "test@test.com";
        uint256 commitmentRand = uint256(93845);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        vm.expectEmit();
        emit UnclaimedStateRegistered(
            recipientEmailAddrCommit,
            testExtensionAddr,
            walletAddr,
            block.timestamp + unclaimedFundExpirationDuration, // should be the default expiration time
            state,
            commitmentRand,
            emailAddr
        );
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            commitmentRand,
            emailAddr
        );
        vm.stopPrank();
    }

    function test_RevertIf_ExtensionDontRegisterUnclaimedFunds_External() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        vm.expectRevert("unclaimed state registration failed");
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            0,
            ""
        );
        vm.stopPrank();
    }

    function test_RevertIf_RegisterExpiredUnclaimedFunds_External() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        uint expiry = block.timestamp + 31 days;

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        vm.expectRevert("invalid expiry time");
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            abi.encode("(address,uint256)", address(dummyApes), 23),
            expiry,
            0,
            ""
        );
        vm.stopPrank();
    }

    function test_RevertIf_UnclaimedFundExists_External() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        dummyApes.freeMint(sender, 33); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, 2 * unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            abi.encode("(address,uint256)", address(dummyApes), 23),
            0,
            0,
            ""
        );

        vm.expectRevert("unclaimed state exists");
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            abi.encode("(address,uint256)", address(dummyApes), 33),
            0,
            0,
            ""
        );
        vm.stopPrank();
    }

    function test_ClaimUnclaimedState_ToExistingAccount() public {
        address sender = vm.addr(5);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            0,
            ""
        );
        vm.stopPrank();

        // Relayer claim the unclaimed state to account
        vm.startPrank(relayer);
        core.claimUnclaimedState(recipientEmailAddrCommit, emailAddrPointer, mockProof);
        vm.stopPrank();

        assertEq(dummyApes.ownerOf(23), walletAddr, "NFT not transferred to account");
        (, , , bytes memory st, ) = core.unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);
        assertEq(st.length, 0, "unclaimed fund not cleared");
    }

    function test_ClaimUnclaimedState_ToNewlyCreatedAccount() public {
        address sender = vm.addr(7);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes32 newEmailAddrPointer = bytes32(uint256(2001));
        bytes32 newAccountKeyCommit = bytes32(uint256(2002));
        bytes32 newWalletSalt = bytes32(uint256(2003));
        bytes memory newPSIPoint = abi.encodePacked(uint256(2003));
        address relayer2 = vm.addr(3);
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            0,
            ""
        );
        vm.stopPrank();

        // New relayer should be able to create account and claim
        vm.startPrank(relayer2);
        core.registerRelayer(bytes32(uint256(980398)), "relayer3@test.com", "relayer3.com");
        core.createAccount(newEmailAddrPointer, newAccountKeyCommit, newWalletSalt, newPSIPoint, mockProof);
        core.initializeAccount(newEmailAddrPointer, emailDomain, block.timestamp, emailNullifier2, mockProof);

        core.claimUnclaimedState(recipientEmailAddrCommit, newEmailAddrPointer, mockProof);
        vm.stopPrank();

        assertEq(dummyApes.ownerOf(23), walletAddr, "NFT not transferred to account");
        (, , , bytes memory st, ) = core.unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);
        assertEq(st.length, 0, "unclaimed fund not cleared");
    }

    function test_ClaimUnclaimedState_MultipleToNewlyCreatedAccount() public {
        address sender = vm.addr(7);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes32 recipientEmailAddrCommit2 = bytes32(uint256(34));
        bytes32 newEmailAddrPointer = bytes32(uint256(2001));
        bytes32 newAccountKeyCommit = bytes32(uint256(2002));
        bytes32 newWalletSalt = bytes32(uint256(2003));
        bytes memory newPSIPoint = abi.encodePacked(uint256(2003));
        address relayer2 = vm.addr(3);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        dummyApes.freeMint(sender, 33); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, 2 * unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            abi.encode("(address,uint256)", address(dummyApes), 23),
            0,
            0,
            ""
        );
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit2,
            testExtensionAddr,
            abi.encode("(address,uint256)", address(dummyApes), 33),
            0,
            0,
            ""
        );
        vm.stopPrank();

        // New relayer should be able to create account and claim
        vm.startPrank(relayer2);
        core.registerRelayer(bytes32(uint256(980398)), "relayer3@test.com", "relayer3.com");
        core.createAccount(newEmailAddrPointer, newAccountKeyCommit, newWalletSalt, newPSIPoint, mockProof);
        core.initializeAccount(newEmailAddrPointer, emailDomain, block.timestamp, emailNullifier2, mockProof);

        core.claimUnclaimedState(recipientEmailAddrCommit, newEmailAddrPointer, mockProof);
        core.claimUnclaimedState(recipientEmailAddrCommit2, newEmailAddrPointer, mockProof);
        vm.stopPrank();

        assertEq(dummyApes.ownerOf(23), walletAddr, "NFT 23 transferred to account");
        assertEq(dummyApes.ownerOf(33), walletAddr, "NFT 33 transferred to account");
    }

    function test_ClaimUnclaimedState_ToTransportedAccount() public {
        address sender = vm.addr(7);
        bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
        bytes32 newEmailAddrPointer = bytes32(uint256(2001));
        bytes32 newAccountKeyCommit = bytes32(uint256(2002));
        bytes32 newWalletSalt = bytes32(uint256(2003));
        bytes memory newPSIPoint = abi.encodePacked(uint256(2003));
        address relayer2 = vm.addr(3);
        bytes memory state = abi.encode("(address,uint256)", address(dummyApes), 23);

        vm.startPrank(sender);
        dummyApes.freeMint(sender, 23); // Mint a NFT with tokenId 23 to walletAddr
        vm.stopPrank();

        vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);

        vm.startPrank(sender);
        core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
            recipientEmailAddrCommit,
            testExtensionAddr,
            state,
            0,
            0,
            ""
        );
        vm.stopPrank();

        // New relayer should be able to claim for existing unclaied States
        vm.startPrank(relayer2);
        core.registerRelayer(bytes32(uint256(980398)), "relayer3@test.com", "relayer3.com");
        core.transportAccount(
            accountKeyCommit,
            newEmailAddrPointer,
            newAccountKeyCommit,
            newPSIPoint,
            EmailProof({nullifier: emailNullifier2, domain: emailDomain, timestamp: block.timestamp, proof: mockProof}),
            mockProof
        );

        core.claimUnclaimedState(recipientEmailAddrCommit, newEmailAddrPointer, mockProof);
        vm.stopPrank();
    }

    // function test_ClaimUnclaimedState_ShouldSendClaimFeeToRelayer() public {
    //     address sender = vm.addr(7);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     // Relayer claim the unclaimed State to account
    //     vm.startPrank(relayer);
    //     core.claimUnclaimedState(recipientEmailAddrCommit, emailAddrPointer, mockProof);

    //     assertEq(relayer.balance, unclaimedStateClaimGas * maxFeePerGas, "recipient didnt receive claim fee");
    // }

    // function test_RevertIf_ClaimUnclaimedState_CalledByNonRelayer() public {
    //     address sender = vm.addr(7);
    //     address newRelayer = vm.addr(8);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     // Register a new relayer and call unclaim; but not the relayer of account (which is the `relayer` in EmailWalletHelper)
    //     vm.startPrank(newRelayer);
    //     core.registerRelayer(bytes32(uint256(980398)), "relayer3@test.com", "relayer3.com");
    //     vm.expectRevert("invalid relayer for account");
    //     core.claimUnclaimedState(recipientEmailAddrCommit, emailAddrPointer, mockProof);
    //     vm.stopPrank();
    // }

    // function test_RevertIf_ClaimUnclaimedState_IsExpired() public {
    //     address sender = vm.addr(7);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.warp(1000); // Set time to 1000

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     vm.warp(1000 + 31 days); // Expiry time is 30 days (set in EmailWalletCoreTestHelper)

    //     vm.startPrank(relayer);
    //     vm.expectRevert("unclaimed State expired");
    //     core.claimUnclaimedState(recipientEmailAddrCommit, emailAddrPointer, mockProof);
    //     vm.stopPrank();
    // }

    // // Relayer from which the account was transported from should not be able to claim
    // function test_RevertIf_ClaimUnclaimedState_ToNullifiedAccount() public {
    //     address sender = vm.addr(7);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
    //     bytes32 newEmailAddrPointer = bytes32(uint256(2001));
    //     bytes32 newAccountKeyCommit = bytes32(uint256(2002));
    //     bytes memory newPSIPoint = abi.encodePacked(uint256(2003));
    //     address newRelayer = vm.addr(8);

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(newRelayer);
    //     core.registerRelayer(bytes32(uint256(980398)), "relayer3@test.com", "relayer3.com");
    //     core.transportAccount(
    //         accountKeyCommit,
    //         newEmailAddrPointer,
    //         newAccountKeyCommit,
    //         newPSIPoint,
    //         EmailProof({nullifier: emailNullifier2, domain: emailDomain, timestamp: block.timestamp, proof: mockProof}),
    //         mockProof
    //     );
    //     vm.stopPrank();

    //     // Old relayer should not be able to claim
    //     vm.startPrank(relayer);
    //     vm.expectRevert("account not initialized");
    //     core.claimUnclaimedState(recipientEmailAddrCommit, emailAddrPointer, mockProof);
    //     vm.stopPrank();
    // }

    // function test_RevertIf_ClaimUnclaimedState_ToUninitializedAccount() public {
    //     address sender = vm.addr(7);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));
    //     bytes32 newEmailAddrPointer = bytes32(uint256(32334));
    //     bytes32 newAccountKeyCommit = bytes32(uint256(32335));
    //     bytes32 newWalletSalt = bytes32(uint256(32336));
    //     bytes memory newPSI = abi.encodePacked(uint256(32337));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     // Relayer claim the unclaimed State to a newly created account, but not initialized
    //     vm.startPrank(relayer);
    //     core.createAccount(newEmailAddrPointer, newAccountKeyCommit, newWalletSalt, newPSI, mockProof);
    //     vm.expectRevert("account not initialized");
    //     core.claimUnclaimedState(recipientEmailAddrCommit, newEmailAddrPointer, mockProof);
    //     vm.stopPrank();
    // }

    // function test_VoidUnclaimedState() public {
    //     address sender = vm.addr(7);
    //     address voidUser = vm.addr(4);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + 31 days); // Expiry time is 30 days (set in EmailWalletCoreTestHelper)

    //     vm.startPrank(voidUser);
    //     vm.expectEmit();
    //     emit UnclaimedStateReverted(recipientEmailAddrCommit, address(daiToken), 100 ether, sender);
    //     core.voidUnclaimedState(recipientEmailAddrCommit);
    //     vm.stopPrank();

    //     assertEq(daiToken.balanceOf(address(core)), 0, "core contract still have tokens");
    //     assertEq(daiToken.balanceOf(sender), 100 ether, "sender didnt receive tokens");
    //     assertEq(voidUser.balance + sender.balance, unclaimedStateClaimGas * maxFeePerGas, "claim fee not returned correctly");

    //     (, , , uint256 amt, ) = core.unclaimedStateOfEmailAddrCommit(recipientEmailAddrCommit);
    //     assertEq(amt, 0, "unclaimed State not cleared");
    // }

    // function test_RevertIf_VoidUnclaimedState_NotExpired() public {
    //     address sender = vm.addr(7);
    //     address voidUser = vm.addr(4);
    //     bytes32 recipientEmailAddrCommit = bytes32(uint256(32333));

    //     vm.deal(sender, unclaimedStateClaimGas * maxFeePerGas);
    //     daiToken.freeMint(sender, 100 ether);

    //     vm.startPrank(sender);
    //     daiToken.approve(address(core), 100 ether);
    //     core.registerUnclaimedState{value: unclaimedStateClaimGas * maxFeePerGas}(
    //         recipientEmailAddrCommit,
    //         address(daiToken),
    //         100 ether,
    //         0,
    //         0,
    //         ""
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(voidUser);
    //     vm.expectRevert("unclaimed state not expired");
    //     core.voidUnclaimedState(recipientEmailAddrCommit);
    //     vm.stopPrank();
    // }
}
