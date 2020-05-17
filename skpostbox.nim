# Copyright 2020 by Joshua "Skrylar" Cearley,
# Available under the Mozilla Public License, version 2.0,
# https://www.mozilla.org/en-US/MPL/2.0/

import macros
import strformat
import sugar

macro make_postbox*(name, body: untyped): untyped =
    # validate body of our macro
    expectKind(body, nnkStmtList)
    for c in body.children:
        expectKind(c, nnkIdent)
    
    # collect enum entries for discriminator nodes
    var discriminator_nodes = nnkEnumTy.newTree(newEmptyNode())
    for c in body.children:
        discriminator_nodes.add ident(fmt"PB{name}Kind{$c}")
    
    # package up an enum for our variant object
    var discriminator = nnkTypeDef.newTree(
        ident fmt"PB{name}Kind",
        newEmptyNode(),
        discriminator_nodes
    )

    # collect cases for our variant object
    var letter_nodes = nnkRecCase.newTree(
        nnkIdentDefs.newTree(
            ident "kind",
            ident fmt"PB{name}Kind",
            newEmptyNode()
        )
    )

    for c in body.children:
        letter_nodes.add nnkOfBranch.newTree(
            ident fmt "PB{name}Kind{$c}",
            nnkIdentDefs.newTree(
                ident fmt"sealed{$c}",
                c,
                newEmptyNode()
            )
        )
    
    let letter_ident = ident fmt"PB{name}Letter"

    # package up variant type for our messages
    var letter = nnkTypeDef.newTree(
        letter_ident,
        newEmptyNode(),
        nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree(
                letter_nodes
            )
        )
    )

    #! if we don't do this, quote will gensym parameter names and
    #! auto-complete will show stupid names like "postbox`gensym12610090"
    let ipostbox = ident "postbox"
    let iletter = ident "letter"

    let ipontoon = ident fmt"{name}Pontoon"
    let idestruct = ident "=destroy"
    let icopy = ident "="

    # work out deliverer procs
    var deliverers = nnkStmtList.newTree()

    var moop = quote:
        proc maybe_init(self: var `name`) =
            if self.pontoon == nil:
                self.pontoon = new(`ipontoon`)
    deliverers.add moop

    moop = quote:
        proc `idestruct`*(self: var `name`) =
            if self.pontoon != nil:
                incl self.pontoon.flags, Disposed
                self.pontoon.mail.reset
                self.pontoon = nil
    deliverers.add moop

    # mailboxes have unique owners, so we must kill the copy constructor here
    moop = quote:
        proc `icopy`*(dest: var `name`; src: `name`) {.error.} =
            `idestruct`(dest)
            dest.pontoon = src.pontoon
    deliverers.add moop

    let ibox = ident "box"
    moop = quote:
        proc post*(`ibox`: var `ipontoon`; `iletter`: `letter_ident`) =
            box.mail.add(`iletter`)
    deliverers.add moop

    for c in body.children:
        var letter_type = ident fmt"PB{name}Letter"
        var discriminator = ident fmt"PB{name}Kind{$c}"
        var sealed = ident fmt"sealed_{$c}"
        var p = quote:
            proc get_deliverer*(`ipostbox`: var `name`,
                `iletter`: type[`c`]): PostboxDeliverer =
                    maybe_init(`ipostbox`)
                    return get_deliverer(`ipostbox`.pontoon,
                        proc(`ipostbox`, `iletter`: pointer) {.cdecl.} =
                            var a = cast[ref `ipontoon`](`ipostbox`)
                            var b = cast[ptr `c`](`iletter`)
                            a[].post(`letter_type`(kind: `discriminator`, `sealed`: b[])))
        deliverers.add p

    # build the internal mailbox object
    var pontoon = nnkTypeDef.newTree(
        ipontoon,
        newEmptyNode(),
        nnkObjectTy.newTree(
            newEmptyNode(),
            nnkOfInherit.newTree(
                ident "PostboxBase"
            ),
            nnkRecList.newTree(
                nnkIdentDefs.newTree(
                    newIdentNode("mail"),
                    nnkBracketExpr.newTree(
                        newIdentNode("seq"),
                        letter_ident
                    ),
                    newEmptyNode()
                )
            )
        )
    )

    # now the unique pointer that owns the mailbox
    var mailbox = nnkTypeDef.newTree(
        nnkPostfix.newTree(
            newIdentNode("*"),
            name
        ),
        newEmptyNode(),
        nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree(
                nnkIdentDefs.newTree(
                    newIdentNode("pontoon"),
                    nnkRefTy.newTree(
                        ipontoon
                    ),
                    newEmptyNode()
                )
            )
        )
    )

    return nnkStmtList.newTree(
        nnkTypeSection.newTree(
            discriminator,
            letter,
            pontoon,
            mailbox
        ),
        deliverers
    )

type
    PostboxFlag* = enum
        Disposed
    
    PostboxFlags* = set[PostboxFlag]

    PostboxBase* = object of RootObj
        flags: PostboxFlags

    PostboxDeliverer* = object
        postbox: ref PostboxBase
        actuator: proc(postbox, letter: pointer) {.cdecl.}

proc dead*(self: PostboxDeliverer): bool =
    ## Checks if the postbox this deliverer is attached to is dead.
    return Disposed in self.postbox.flags

proc post*(self: PostboxDeliverer; letter: pointer): bool =
    ## Posts the message to a post box. Returns true if it was posted or
    ## false if the postbox is dead. Internal function for event emitters
    ## to use.
    if self.dead: return false
    self.actuator(cast[pointer](self.postbox), letter)
    return true

proc get_deliverer*(box: ref PostboxBase;
    actuator: proc(a, b: pointer) {.cdecl.}): PostboxDeliverer =
        if likely(Disposed notin box.flags):
            result.postbox = box
            result.actuator = actuator
        # else: result is initialized to zero

type
    MicrowaveSetting* = object
        heat*: int
    MicrowaveBeep* = object

expandMacros:
    make_postbox(Donk):
        MicrowaveBeep
        MicrowaveSetting

# type
#   PBDonkKind = enum
#     PBDonkKindMicrowaveBeep, PBDonkKindMicrowaveSetting
#   PBDonkLetter = object
#     case kind: PBDonkKind
#     of PBDonkKindMicrowaveBeep:
#       sealedMicrowaveBeep: MicrowaveBeep
#     of PBDonkKindMicrowaveSetting:
#       sealedMicrowaveSetting: MicrowaveSetting
  
#   Donk = object
#     mail: seq[PBDonkLetter]

# proc post(box: var Donk; letter: PBDonkLetter) =
#   add(box.mail, letter)

# proc get_deliverer(postbox: type[Donk]; letter: type[MicrowaveBeep]): proc (
#     postbox, letter: pointer) {.cdecl.} =
#   return proc (postbox, letter: pointer) {.cdecl.} =
#     var a`gensym12765120 = cast[ptr Donk](postbox)
#     var b`gensym12765121 = cast[ptr MicrowaveBeep](letter)
#     var c`gensym12765122 = PBDonkLetter(kind: PBDonkKindMicrowaveBeep,
#                                      sealed_MicrowaveBeep: b`gensym12765121[])
#     a`gensym12765120[].post(c`gensym12765122)

# proc get_deliverer(postbox: type[Donk]; letter: type[MicrowaveSetting]): proc (
#     postbox, letter: pointer) {.cdecl.} =
#   return proc (postbox, letter: pointer) {.cdecl.} =
#     var a`gensym12765123 = cast[ptr Donk](postbox)
#     var b`gensym12765124 = cast[ptr MicrowaveSetting](letter)
#     var c`gensym12765125 = PBDonkLetter(kind: PBDonkKindMicrowaveSetting, sealed_MicrowaveSetting: b`gensym12765124[])
#     a`gensym12765123[].post(c`gensym12765125)

var x = Donk()
var y = MicrowaveBeep()
var z = MicrowaveSetting(heat: 500)

var h = get_deliverer(x, MicrowaveBeep)
var e = MicrowaveBeep()
discard h.post(addr e)
