import XCTest
@testable import Application

final class AppTests: XCTestCase {
    func testListQueryDefaults() {
        let q = ListQuery(page: nil, perPage: nil, sortBy: nil, sortOrder: "DESC", search: nil)
        XCTAssertEqual(q.normalizedPage, 1)
        XCTAssertEqual(q.normalizedPerPage, 20)
        XCTAssertFalse(q.ascending)
    }

    func testPermissionKeysIncludeCorePermissions() {
        XCTAssertTrue(PermissionKey.all.contains(PermissionKey.boardView))
        XCTAssertTrue(PermissionKey.all.contains(PermissionKey.taskCreate))
        XCTAssertTrue(PermissionKey.all.contains(PermissionKey.userManage))
    }

    func testRoleNamesAreStable() {
        XCTAssertEqual(RoleName.admin, "admin")
        XCTAssertEqual(RoleName.manager, "manager")
        XCTAssertEqual(RoleName.assignee, "assignee")
        XCTAssertEqual(RoleName.viewer, "viewer")
    }
}
