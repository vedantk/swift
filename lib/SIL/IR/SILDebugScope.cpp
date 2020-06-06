//===--- SILDebugScope.cpp - DebugScopes for SIL code ---------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
///
/// \file
///
/// This file defines a container for scope information used to
/// generate debug info.
///
//===----------------------------------------------------------------------===//

#include "swift/SIL/SILDebugScope.h"
#include "swift/SIL/SILFunction.h"
#include "swift/SIL/SILModule.h"

using namespace swift;

SILDebugScope::SILDebugScope(SILLocation Loc, SILFunction *SILFn,
                             const SILDebugScope *ParentScope,
                             const SILDebugScope *InlinedCallSite)
    : Loc(Loc), InlinedCallSite(InlinedCallSite) {
  if (ParentScope)
    Parent = ParentScope;
  else
    Parent = SILFn;
}

SILDebugScope *SILDebugScope::get(SILModule &M, SILLocation Loc,
                                  SILFunction *SILFn,
                                  const SILDebugScope *ParentScope,
                                  const SILDebugScope *InlinedCallSite) {
  ScopeKey key{{Loc.getOpaquePointerValue(), SILFn},
               {ParentScope, InlinedCallSite}};
  SILDebugScope *&scope = M.DebugScopes[key];
  if (!scope)
    scope = new (M) SILDebugScope(Loc, SILFn, ParentScope, InlinedCallSite);
  assert(!scope->isArtificial() && "Expected non-artificial scope");
  return scope;
}

SILDebugScope *SILDebugScope::getArtificial(SILModule &M, SILLocation Loc) {
  // Each time an artificial scope is requested, create a fresh (unique) scope.
  // In practice, we don't create any redundant scopes due to this, because the
  // API is only used for artificial functions and trap failure messages. If
  // that changes, we'd need to unique the scope on something other than just
  // the SILLocation, because it's often auto-generated (i.e. its hash is 0).
  return new (M) SILDebugScope(Loc, nullptr, nullptr, nullptr);
}

const SILDebugScope *
SILDebugScope::cloneForFunction(SILFunction *SILFn, const SILDebugScope *Orig) {
  assert(SILFn && "No function to make a clone for");

  // Empty scopes and artificial scopes don't need to be cloned.
  if (!Orig || Orig->isArtificial())
    return Orig;

  SILModule &M = SILFn->getModule();

  // For inlined code, cloning doesn't affect the parent debug scope.
  auto *NewInlinedCallSite = cloneForFunction(SILFn, Orig->InlinedCallSite);
  if (NewInlinedCallSite) {
    auto *OrigParent = Orig->Parent.dyn_cast<const SILDebugScope *>();
    return get(M, Orig->Loc, SILFn, OrigParent, NewInlinedCallSite);
  }

  assert(!NewInlinedCallSite && !Orig->InlinedCallSite &&
         "Inlining should be handled already");

  if (auto *ParentFn = Orig->Parent.dyn_cast<SILFunction *>()) {
    // If the scope is already rooted at the cloned function, the job is done.
    if (ParentFn == SILFn) {
      assert(get(M, Orig->Loc, SILFn) == Orig && "Cloned scope not unique?");
      return Orig;
    }

    assert(!Orig->InlinedCallSite &&
           "Child of root scope has an inlined call site?");
    return get(M, Orig->Loc, SILFn);
  }

  auto *OrigParent = Orig->Parent.dyn_cast<const SILDebugScope *>();
  assert(OrigParent && "Must be nested scope");
  auto *NewParent = cloneForFunction(SILFn, OrigParent);
  return get(M, Orig->Loc, SILFn, NewParent);
}

SILFunction *SILDebugScope::getInlinedFunction() const {
  if (Parent.isNull())
    return nullptr;

  const SILDebugScope *Scope = this;
  while (Scope->Parent.is<const SILDebugScope *>())
    Scope = Scope->Parent.get<const SILDebugScope *>();
  assert(Scope->Parent.is<SILFunction *>() && "orphaned scope");
  return Scope->Parent.get<SILFunction *>();
}

SILFunction *SILDebugScope::getParentFunction() const {
  if (InlinedCallSite)
    return InlinedCallSite->getParentFunction();
  if (auto *ParentScope = Parent.dyn_cast<const SILDebugScope *>())
    return ParentScope->getParentFunction();
  return Parent.get<SILFunction *>();
}

bool swift::maybeScopeless(SILInstruction &I) {
  if (I.getFunction()->isBare())
    return true;
  return !isa<DebugValueInst>(I) && !isa<DebugValueAddrInst>(I);
}

void SILDebugScope::updateScopeForClone(SILFunction &NewFn) {
  const SILDebugScope *OrigDS = NewFn.getDebugScope();
  assert(OrigDS && "Cloned function with no debug scope");
  auto *SILFn = OrigDS->Parent.get<SILFunction *>();
  if (SILFn != &NewFn) {
    // Some clients of SILCloner copy over the original function's debug scope.
    // Create a new one here.
    // FIXME: Audit all call sites and make them create the function debug
    // scope.
    SILFn->setInlined();
    auto *NewDS = cloneForFunction(&NewFn, OrigDS);
    NewFn.setDebugScope(NewDS);
  }
}

void SILDebugScope::updateScopeForClonedInst(SILInstruction &I) {
  auto *NewFn = I.getFunction();
  auto *NewDS = cloneForFunction(NewFn, I.getDebugScope());
  I.setDebugScope(NewDS);
}
