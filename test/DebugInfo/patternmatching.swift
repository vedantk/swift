// RUN: %target-swift-frontend -primary-file %s -emit-ir -g -o %t.ll
// RUN: %FileCheck %s < %t.ll
// RUN: %FileCheck --check-prefix=CHECK-SCOPES %s < %t.ll
// RUN: %target-swift-frontend -emit-sil -emit-verbose-sil -primary-file %s -o - | %FileCheck %s --check-prefix=SIL-CHECK

func markUsed<T>(_ t: T) {}

// CHECK-SCOPES: define {{.*}}classifyPoint2
func classifyPoint2(_ p: (Double, Double)) {
    func return_same (_ input : Double) -> Double
    {
        return input; // return_same gets called in both where statements
    }

switch p {
    // CHECK-SCOPES: call void @llvm.dbg{{.*}}metadata [[P:![0-9]+]]
    // CHECK-SCOPES-SAME:                              !dbg [[PLOC:![0-9]+]]
    //
    // Just need two shadow slots for x & y in this switch.
    //
    // CHECK-SCOPES: call void @llvm.dbg{{.*}}metadata [[X1:![0-9]+]],
    // CHECK-SCOPES-SAME:                              !dbg [[X1LOC:![0-9]+]]
    // CHECK-SCOPES: call void @llvm.dbg{{.*}}metadata [[Y1:![0-9]+]],
    // CHECK-SCOPES-SAME:                              !dbg [[Y1LOC:![0-9]+]]
    case (let x, let y) where
      // CHECK:   call {{.*}}double {{.*}}return_same{{.*}}, !dbg ![[LOC1:.*]]
      // CHECK: br {{.*}}, label {{.*}}, label {{.*}}, !dbg ![[LOC2:.*]]
      // CHECK: call{{.*}}markUsed{{.*}}, !dbg ![[LOC3:.*]]
      // CHECK: ![[LOC1]] = !DILocation(line: [[@LINE+2]],
      // CHECK: ![[LOC2]] = !DILocation(line: [[@LINE+1]],
                        return_same(x) == return_same(y):
      // CHECK: ![[LOC3]] = !DILocation(line: [[@LINE+1]],
      markUsed(x)
      // SIL-CHECK:  dealloc_stack{{.*}}line:[[@LINE-1]]:17:cleanup
      // Verify that the branch has a location >= the cleanup.
      // SIL-CHECK-NEXT:  br{{.*}}auto_gen
    case (let x, let y) where x == -y:
      markUsed(x)
    case (let x, let y) where x >= -10 && x < 10 && y >= -10 && y < 10:
      markUsed(x)
    case (let x, let y):
      markUsed(x)
    }

switch p {
    // CHECK-SCOPES: call void @llvm.dbg{{.*}}metadata [[X2:![0-9]+]],
    // CHECK-SCOPES-SAME:                              !dbg [[X2LOC:![0-9]+]]
    // CHECK-SCOPES: call void @llvm.dbg{{.*}}metadata [[Y3:![0-9]+]],
    // CHECK-SCOPES-SAME:                              !dbg [[Y3LOC:![0-9]+]]
    case (let x, let y) where x == 0:
      if y == 0 { markUsed(x) }
      else      { markUsed(y) } // SIL-CHECK-NOT: br{{.*}}line:[[@LINE]]:31:cleanup
    case (let x, let y): do {
      if y == 0 { markUsed(x) }
      else      { markUsed(y) }
    } // SIL-CHECK: br{{.*}}line:[[@LINE]]:5:cleanup
}

// Verify that all variables end up in their respective switch scopes.

// The switch on line 15:
// CHECK-SCOPES: [[X1]] = !DILocalVariable(name: "x", scope: [[SCOPE1:![0-9]+]],
// CHECK-SCOPES-SAME:                       line: 25
// CHECK-SCOPES: [[SCOPE1]] = distinct !DILexicalBlock({{.*}}line: 15
// CHECK-SCOPES: [[X1LOC]] = !DILocation(line: 25, 
// CHECK-SCOPES-SAME:                     scope: [[SCOPE1]])
// CHECK-SCOPES: [[Y1]] = !DILocalVariable(name: "y", scope: [[SCOPE1]],
// CHECK-SCOPES-SAME:                       line: 25

// The switch on line 45:
// CHECK-SCOPES: [[X2]] = !DILocalVariable(name: "x", scope: [[SCOPE2:![0-9]+]],
// CHECK-SCOPES-SAME:                       line: 50
// CHECK-SCOPES: [[SCOPE2]] = distinct !DILexicalBlock({{.*}}line: 45
// CHECK-SCOPES: [[X2LOC]] = !DILocation(line: 50
// CHECK-SCOPES-SAME:                     scope: [[SCOPE2]])
// CHECK-SCOPES: [[Y3]] = !DILocalVariable(name: "y", scope: [[SCOPE2]]
// CHECK-SCOPES-SAME:                       line: 50
// CHECK-SCOPES: [[Y3LOC]] = !DILocation(line: 50
// CHECK-SCOPES-SAME:                     scope: [[SCOPE2]])

// CHECK: !DILocation(line: [[@LINE+1]],
}
