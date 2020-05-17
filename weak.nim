import sugar
import sequtils

type
    Handler = object
        id: int
        marker: int

var registry: seq[ptr Handler]

proc dump_registry() =
    echo registry.map(x => cast[int](x))
    # discard

proc `=`*(dest: var Handler; src: Handler) =
    dest.id = registry.len + 1
    registry.add addr dest
    echo "handle copied"

proc `=sink`*(dest: var Handler; src: Handler) =
    dest.id = src.id
    registry[dest.id-1] = addr dest
    echo "handle moved"

proc `=destroy`*(dest: var Handler) =
    if dest.id != 0:
        # this is what 'del' does, but we add the ID fixup step
        let did = dest.id-1
        registry[did] = registry[registry.high]
        registry[did].id = did+1
        setLen(registry, registry.len-1)

    echo "handle destroyed"

proc marksweep(marker: int) =
    for c in registry:
        if unlikely(c == nil): continue
        c.marker = marker

#! must be a var parameter because the address of `result` is meaningless
proc get_handle(result: var Handler) =
    result.id = registry.len + 1
    registry.add addr result

proc jengu(thing: Handler) =
    var x = thing
    echo "I have become the potato: ", x

proc bill() =
    var x: Handler
    dump x
    get_handle(x)
    echo cast[int](addr x)

    var y = x # copied
    dump_registry()
    jengu(y)

    marksweep(22)
    dump_registry()

    dump x

bill()
dump_registry()
