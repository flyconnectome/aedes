# xform_aedes requires exactly one side to be aedes

    Code
      xform_aedes(aedes_pt(), sample = "FlyWire", reference = "JRC2018F")
    Condition
      Error:
      ! One of `sample` and `reference` must be "aedes", and the other a fly space.
        Got sample = "FlyWire", reference = "JRC2018F".
        Neither is Aedes: to move between two fly spaces see `nat.templatebrains::xform_brain()`.

---

    Code
      xform_aedes(aedes_pt(), sample = "aedes", reference = "aedes")
    Condition
      Error:
      ! One of `sample` and `reference` must be "aedes", and the other a fly space.
        Got sample = "aedes", reference = "aedes".
        Both are Aedes: to move within Aedes space see `aedes_mirror()`.

