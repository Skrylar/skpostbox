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
    let ioutput = ident "output"

    # work out deliverer procs
    var deliverers = nnkStmtList.newTree()
    for c in body.children:
        var letter_type = ident fmt"PB{name}Letter"
        var discriminator = ident fmt"PB{name}Kind{$c}"
        var sealed = ident fmt"sealed_{$c}"
        var p = quote:
            proc get_deliverer*(`ipostbox`: var `name`,
                `iletter`: type[`c`],
                `ioutput`: var PostboxDeliverer) =
                    get_deliverer(`ipostbox`, `ioutput`,
                        proc(`ipostbox`, `iletter`: pointer) {.cdecl.} =
                            var a = cast[ptr `name`](`ipostbox`)
                            var b = cast[ptr `c`](`iletter`)
                            var c = `letter_type`(kind: `discriminator`, `sealed`: b[])
                            a[].post(c))
        deliverers.add p

    # build up actual mailbox object
    var mailbox = nnkTypeDef.newTree(
        nnkPostfix.newTree(
            newIdentNode("*"),
            name
        ),
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

    let ibox = ident "box"
    var poster = quote:
        proc post*(`ibox`: var `name`; `iletter`: `letter_ident`) =
            box.mail.add(`iletter`)

    return nnkStmtList.newTree(
        nnkTypeSection.newTree(
            discriminator,
            letter,
            mailbox
        ),
        poster,
        deliverers
    )

type
    PostboxDeliverer* = object
        postbox: pointer ## Which postbox this deliverer is from
        id: int ## ID of this deliverer in the postboxes tracking array
        actuator: proc(postbox, letter: pointer) {.cdecl.}

    PostboxBase* = object of RootObj
        handles: seq[ptr PostboxDeliverer]

proc dead*(self: PostboxDeliverer): bool =
    ## Checks if the postbox this deliverer is attached to is dead.
    return self.postbox == nil

proc post*(self: PostboxDeliverer; letter: pointer): bool =
    ## Posts the message to a post box. Returns true if it was posted or
    ## false if the postbox is dead. Internal function for event emitters
    ## to use.
    if self.dead: return false
    self.actuator(self.postbox, letter)
    return true

proc send_death_notice*(list: seq[ptr PostboxDeliverer]) =
    ## Notifies every post box in the sequence that its postbox is now dead.
    ## Internal function for postboxes to use.
    for x in list:
        x.postbox = nil

proc `=`*(dest: var PostboxDeliverer; src: PostboxDeliverer) =
    # ignore self-assignments
    if equalMem(addr dest, unsafeaddr src, PostboxDeliverer.sizeof):
        return
    # copy data and register new copy with the postbox
    dest.postbox = src.postbox
    dest.actuator = src.actuator
    if not dest.dead:
        var p = cast[ptr PostboxBase](dest.postbox)
        dest.id = p.handles.len+1
        p.handles.add addr dest

proc `=destroy`*(dest: var PostboxDeliverer) =
    if dest.dead: return
    var p = cast[ptr PostboxBase](dest.postbox)

    # TODO locking, in threaded builds
    # immitate `del` but update handle id afterward
    let did = dest.id-1
    p.handles[did] = p.handles[p.handles.high]
    p.handles[did].id = did+1
    setLen(p.handles, p.handles.len-1)

    dest.postbox = nil

proc get_deliverer*(box: var PostboxBase;
    output: var PostboxDeliverer;
    actuator: proc(a, b: pointer) {.cdecl.}) =
        `=destroy`(output)
        output.postbox = addr box
        output.id = box.handles.len+1
        output.actuator = actuator
        box.handles.add(addr output)

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

dump x

var h: PostboxDeliverer
get_deliverer(x, MicrowaveBeep, h)
var e = MicrowaveBeep()
dump h.post(addr e)

dump x
