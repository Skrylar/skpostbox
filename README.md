`skpostbox` automatically generates the plumbing for a traditional
message pump system.

# Overview

Postboxes have a few parts:

  - Letter  
    An object that will be later stored in to a mailbox.

  - Envelope  
    A variant object which holds different kinds of letters.

  - Pontoon  
    A `ref` object; it holds a list of unprocessed envelopes and a
    dead-man trigger.

  - Postbox  
    A handle which is a unique pointer to protect the pontoon.

  - Deliverer  
    An object who wraps letters in envelopes and leave them in
    postboxes.

<div class="note">

Postboxes are strictly **single owner**. They cannot be copied, only
moved.

Also when the postbox is destroyed the pontoons are marked as `Disposed`
so no more messages can be processed. This creates the standard "weak
reference" pattern. Event senders are expected to lazily remove
deliverers with dead pontoons as they attempt to send events.

</div>

## License

  - `skpostbox` is available under Mozilla Public License, version 2
    (MPL-2.)

# Examples

## Defining a postbox

**Define your events.**

    type
        MicrowaveSetting* = object
            heat*: int
    
        MicrowaveBeep* = object

**List the events a postbox will handle.**

    make_postbox(Donk):
        MicrowaveBeep
        MicrowaveSetting

## Instantiating a postbox

    var x = Donk()

Postboxes can be moved but not copied.

## Sending events to a postbox

**Create posters who send single types of letters.**

    var beep_source = Poster[MicrowaveBeep]()
    var setting_source = Poster[MicrowaveSetting]()

**Connect posters to postboxes.**

    connect(x, beep_source)
    connect(x, setting_source)

**Send letters.**

    beep_source.post y
    setting_source.post z

## Processing queued events

**Using the case dispatcher.**

    x.case_dispatch_all_unread(e):
    of MicrowaveSetting:
        echo "temperature is now ", e.heat
    of MicrowaveBeep:
        echo "beeeep"
    else:
        discard

**Manually dispatching on event kind.**

    for event in x:
        case event.kind:
        of PBDonkKindEmpty: discard
        of PBDonkKindMicrowaveSetting:
            echo "microwave changed to ", event.sealedMicrowaveSetting.heat
        of PBDonkKindMicrowaveBeep:
            echo "beeep"

<div class="note">

Manual dispatch is not recommended since it relies on knowing how
`make_postbox` mangles names.

</div>

# Thread Safety

Mailboxes are not presently thread-safe.

1.  Laziest version: put a lock around post and iterate. Makes it thread
    safe (technically) but has the most contention.

TODO: look in to the various clever ways to make this safe (lock and
lock-free.)

# Weak References

1.  Double-ref: objects contain `ref` objects called *tombstones*. The
    tombstone is a `ptr` back to the original object. Upon `=destroy`
    you set the back pointer in the tombstone to nil. Then strong
    references become copies of the `ref` to the base object and weaks
    are `ref` to the tombstone.

2.  Pontoons: weak references are simply `ref` to the pontoon (which can
    be handed out, it "floats") which contains a flag to indicate it has
    been *disposed* \[1\]. A *buoy* object then acts as the unique owner
    of the pontoon. The buoy’s `=destroy` does a partial
    deinitialization of the pontoon and sets the disposed flag.

I originally used *double-ref* which is clean and straightforward (`ref
Tombstone` is weak, `ref Frobnicator` is strong.) It also adds another
heap allocation to track the tombstone.

Switched to pontoons because the buoy lives on the stack (or otherwise
inline to the object owning it.) So there is one ref for the postbox
itself.

In Postbox’es case access to the postbox itself is largely restricted.
The buoy belongs to whoever is going to pick up and process messages
from the postbox. Weak references belong to the deliverer objects you
request form a postbox. No code other than the automatically generated
boilerplate touches the internals of the postbox system.

1.  This is similar to how `IDisposable` works in C\#.
