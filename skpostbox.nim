# Copyright 2020 by Joshua "Skrylar" Cearley,
# Available under the Mozilla Public License, version 2.0,
# https://www.mozilla.org/en-US/MPL/2.0/

import macros
import strformat

macro case_dispatch_all_unread*(box: typed; accessor: untyped; body: varargs[untyped]): untyped =
    ## Dispatches each unread message; conjoins an iterator with a case-of
    ## which hides the name mangling 
    let ievent = genSym(nskForVar, "event")

    var dispatcher = nnkCaseStmt.newTree(
        nnkDotExpr.newTree(
            ievent,
            ident "kind"
        )
    )

    for c in body.children:
        case c.kind:
        of nnkOfBranch:
            # replace "case Foo" with "case PB{Postbox}KindFoo"
            # insert "template accessor = event.sealed_Foo"

            let whozit = $c[0]
            # XXX praying this always returns the non-FQN name
            c[0] = ident fmt"PB{getTypeInst(box)}Kind{whozit}"
            var localaccessor = nnkTemplateDef.newTree(
                accessor,
                newEmptyNode(),
                newEmptyNode(),
                nnkFormalParams.newTree(ident whozit),
                nnkPragma.newTree(ident "used"),
                newEmptyNode(),
                nnkStmtList.newTree(
                    nnkDotExpr.newTree(
                        ievent,
                        ident fmt"sealed_{whozit}"
                    )
                )
            )
            c[1].insert(0, localaccessor)
            dispatcher.add c
        of nnkElse:
            # no special transform needed for this
            dispatcher.add c
        else:
            error("Argument must be an Of-Clause or an Else.", c)

    result = nnkForStmt.newTree(
        ievent,
        box,
        nnkStmtList.newTree(dispatcher)
    )

macro make_postbox*(name, body: untyped): untyped =
    ## Creates a new postbox type, with supporting infrastructure.

    # validate body of our macro
    expectKind(body, nnkStmtList)
    for c in body.children:
        expectKind(c, nnkIdent)
    
    # collect enum entries for discriminator nodes
    var discriminator_nodes = nnkEnumTy.newTree(newEmptyNode())
    discriminator_nodes.add ident(fmt"PB{name}KindEmpty")
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

    let iempty = ident fmt "PB{name}KindEmpty"
    letter_nodes.add nnkOfBranch.newTree(
        iempty,
        nnkIdentDefs.newTree(
            ident "nothing",
            ident "void",
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
        proc post*(`ibox`: var `ipontoon`; `iletter`: owned `letter_ident`) =
            box.mail.add(`iletter`)
    deliverers.add moop

    moop = quote:
        iterator items*(`ibox`: var `name`): `letter_ident` =
            var i = 0
            let c = `ibox`.pontoon.mail.len
            if unlikely(Dispatching in `ibox`.pontoon.flags):
                raise newException(Defect, "Only one mailbox reader is allowed")
            if `ibox`.pontoon != nil:
                incl `ibox`.pontoon.flags, Dispatching
                defer: excl `ibox`.pontoon.flags, Dispatching
                while i < c:
                    # return the message
                    yield `ibox`.pontoon.mail[i]
                    # now clear it from the box
                    # XXX this causes mysterious compiler crashes sometimes
                    `ibox`.pontoon.mail[i] = `letter_ident`(kind: `iempty`)
                    inc i
                setLen(`ibox`.pontoon.mail, 0)
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
                            a[].post(`letter_type`(kind: `discriminator`, `sealed`: move(b[]))))
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
        Disposed, Dispatching
    
    PostboxFlags* = set[PostboxFlag]

    PostboxBase* = object of RootObj
        flags*: PostboxFlags

    PostboxDeliverer* = object
        postbox: ref PostboxBase
        actuator: proc(postbox, letter: pointer) {.cdecl.}
    
    Poster*[T] = object
        destinations*: seq[PostboxDeliverer]

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

proc connect*[E,T](postbox: var T; poster: var Poster[E]) =
    mixin get_deliverer
    poster.destinations.add(get_deliverer(postbox, E))

proc post*[T](poster: var Poster[T]; message: ptr T) =
    ## Sends a message to every destination of the poster.
    ## Also unsubscribes any destinations who have since gone invalid.
    var i = 0
    while i < poster.destinations.len:
        if not poster.destinations[i].post(message):
            poster.destinations.del(i)
        inc i

proc post*[T](poster: var Poster[T]; message: T) =
    poster.post(unsafeaddr message)
