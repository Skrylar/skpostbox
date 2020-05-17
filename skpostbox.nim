import macros
import strformat

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

    var letter = nnkTypeDef.newTree(
        ident fmt"PB{name}Letter",
        newEmptyNode(),
        nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree(
                letter_nodes
            )
        )
    )

    return nnkTypeSection.newTree(
        discriminator,
        letter
    )

expandMacros:
    type
        VegetalCooked* = object
            wot*: int
    make_postbox(Spigglebot):
        VegetalCooked
