"""Provisional content defs for 4.0 room types that SIM has named but not yet put in content/buildings.json."""


def provisional(tid):
    try:
        import rooms_v4ind as RV
    except ModuleNotFoundError:
        return {}
    return RV.PROVISIONAL_DEF if tid in RV.V4_ROOMS else {}
