import skpostbox

# tag::define-events[]
type
    MicrowaveSetting* = object
        heat*: int

    MicrowaveBeep* = object
# end::define-events[]

# tag::make-postbox[]
make_postbox(Donk):
    MicrowaveBeep
    MicrowaveSetting
# end::make-postbox[]

# tag::instance[]
var x = Donk()
# end::instance[]

var y = MicrowaveBeep()
var z = MicrowaveSetting(heat: 500)

# tag::sender[]
var beep_source = Poster[MicrowaveBeep]()
var setting_source = Poster[MicrowaveSetting]()
# end::sender[]

# tag::connect[]
connect(x, beep_source)
connect(x, setting_source)
# end::connect[]

# tag::post[]
beep_source.post y
setting_source.post z
# end::post[]

# tag::dispatch-macro[]
x.case_dispatch_all_unread(e):
of MicrowaveSetting:
    echo "temperature is now ", e.heat
of MicrowaveBeep:
    echo "beeeep"
else:
    discard
# end::dispatch-macro[]

# tag::dispatch-manual[]
for event in x:
    case event.kind:
    of PBDonkKindEmpty: discard
    of PBDonkKindMicrowaveSetting:
        echo "microwave changed to ", event.sealedMicrowaveSetting.heat
    of PBDonkKindMicrowaveBeep:
        echo "beeep"
# end::dispatch-manual[]