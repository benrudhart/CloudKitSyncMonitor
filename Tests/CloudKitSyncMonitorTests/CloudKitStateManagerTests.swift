//
//  SyncMonitorTests.swift
//  
//
//  Created by Grant Grueninger on 9/23/20.
//

import Foundation

import XCTest
import CoreData
@testable import CloudKitSyncMonitor

@MainActor
final class CloudKitStateManagerTests: XCTestCase {
    func testCanDetectImportError() {
        // Given an active network connection
        let succeeded = SyncState.succeeded(started: .now, ended: .now)
        let stateManager = CloudKitStateManager(setupState: succeeded)

        // When NSPersistentCloudKitContainer reports an unsuccessful import

        let event = SyncEventMock(type: .import, startDate: .now, endDate: .now, succeeded: false, error: MockError.failed)
        stateManager.setState(from: event)

        // and importState failed
        if case .failed(_, _, let aError) = stateManager.importState,
           let mockError = aError as? MockError {
            XCTAssertEqual(mockError, .failed)
        } else {
            XCTAssert(false, "importState should be .failed")
        }
    }

    func testCanDetectExportError() {
        // Given an active network connection
        let succeeded = SyncState.succeeded(started: .now, ended: .now)
        let stateManager = CloudKitStateManager(setupState: succeeded, importState: succeeded)

        // When NSPersistentCloudKitContainer reports an unsuccessful import
        let event = SyncEventMock(type: .export, startDate: .now, endDate: .now, succeeded: false, error: MockError.failed)
        stateManager.setState(from: event)

        // and exportState failed
        if case .failed(_, _, let aError) = stateManager.exportState,
            let mockError = aError as? MockError {
             XCTAssertEqual(mockError, .failed)
        } else {
            XCTAssert(false, "exportState should be .failed")
        }
    }

    func testCanDetectImportSuccess() {
        // Given an active network connection
        let stateManager = CloudKitStateManager()

        // When NSPersistentCloudKitContainer reports a successful import
        let event = SyncEventMock(type: .import, startDate: .now, endDate: .now, succeeded: true, error: nil)
        stateManager.setState(from: event)

        // Then importError is nil
        XCTAssertNil(stateManager.importState.error)
        XCTAssertTrue(stateManager.importState.succeeded)
    }

    func testCanDetectExportSuccess() {
        // Given an active network connection
        let stateManager = CloudKitStateManager()

        // When NSPersistentCloudKitContainer reports a successful export
        let event = SyncEventMock(type: .export, startDate: .now, endDate: .now, succeeded: true, error: nil)
        stateManager.setState(from: event)

        // Then exportError is nil
        XCTAssertNil(stateManager.exportState.error)
        XCTAssertTrue(stateManager.exportState.succeeded)
    }

    func testSetsStatusToInProgressWhenEventHasNoEndDate() {
        // Given an active network connection
        let stateManager = CloudKitStateManager()

        // When NSPersistentCloudKitContainer reports an event with a start date but no end date
        let event = SyncEventMock(type: .export, startDate: .now, endDate: nil, succeeded: false, error: nil)
        stateManager.setState(from: event)

        // Then exportError is nil
        XCTAssertNil(stateManager.exportState.error)
        XCTAssertTrue(stateManager.exportState.inProgress)
    }

    func testSetsStatusToNotStartedOnStartup() {
        // Given an active network connection
        let stateManager = CloudKitStateManager(importState: .notStarted)

        // When we check status before an event has been reported
        // Then the status is ".notStarted"
        XCTAssertTrue(stateManager.importState.notStarted)
    }
}

private struct SyncEventMock: SyncEvent {
    let type: NSPersistentCloudKitContainer.EventType
    let startDate: Date
    let endDate: Date?
    let succeeded: Bool
    let error: Error?
}

private enum MockError: Error, Equatable {
    case failed
}
