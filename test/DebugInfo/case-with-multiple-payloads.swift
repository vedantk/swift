// RUN: %target-swift-frontend -primary-file %s -emit-ir -g -o - | %FileCheck %s -implicit-check-not=llvm.dbg.declare

enum E {
  case one(Int)
  case two(Int)
  case three(String)
}

// CHECK: define {{.*}}switch_on_E
func switch_on_E(e: E) {
  // CHECK: llvm.dbg.declare({{.*}}, metadata [[e:![0-9]+]]
  // CHECK-SAME:                              !dbg [[e_loc:![0-9]+]]
  switch e {
    // Test a case with two let bindings; just need one shadow slot.
    // CHECK: llvm.dbg.declare({{.*}}, metadata [[payload1:![0-9]+]]
    // CHECK-SAME:                              !dbg [[payload1_loc:![0-9]+]]
    case .one(let payload),
         .two(let payload):
      print(payload)

    // Test a case with a let binding for a var of a different type (needs a
    // new shadow slot).
    // CHECK: llvm.dbg.declare({{.*}}, metadata [[payload2:![0-9]+]]
    // CHECK-SAME:                              !dbg [[payload2_loc:![0-9]+]]
    case .three(let payload):
      print(payload)
  }
}

// CHECK: declare void @llvm.dbg.declare

// CHECK: [[e]] = !DILocalVariable(name: "e"

// CHECK: [[payload1]] = !DILocalVariable(name: "payload"
// CHECK-SAME:                            scope: [[SCOPE:![0-9]+]]

// CHECK: [[SCOPE]] = distinct !DILexicalBlock({{.*}}, line: 13

// CHECK: [[payload2]] = !DILocalVariable(name: "payload"
// CHECK-SAME:                            scope: [[SCOPE]]
