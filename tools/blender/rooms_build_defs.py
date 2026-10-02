"""Provisional content defs for 4.0 room types that SIM has named but not yet put in content/buildings.json."""


# 5.0 section 17.1 (coordinator 2026-10-02): the HR office until SIM puts it in content (sizes S/M/L like the civic
# modules; furniture: S/M/L officers 1/2/3 (section 17.2), seats = interview 2 + visitor and waiting chairs, stands =
# kiosk, filing, suggestion box, water cooler).  Told to SIM in docs/requests/ART-HAB-to-SIM.md.
HR_OFFICE = {"name": "HR Office", "category": "civic", "kind": "room", "radius": 6.0, "v5": True, "family": "",
             "size_list": [0, 1, 2], "sizes": {"radius": [6.0, 7.5, 9.6, 9.6]},
             "furniture": {"beds": [0, 0, 0, 0], "seats": [3, 5, 7, 7], "work_slots": [1, 2, 3, 3],
                           "stands": [2, 3, 4, 4], "work_pose": "sit"},
             "anchors_spec": {"reception": "Anchor_Reception_0", "queue": "Anchor_Queue_<i>",
                              "interview": "Anchor_Interview_<i>", "kiosk": "Anchor_Kiosk_0",
                              "filing": "Anchor_Filing_0", "desk": "Anchor_Desk_<i>"}}
V5_PROVISIONAL = {"hr_office": HR_OFFICE}


def provisional(tid):
    if tid in V5_PROVISIONAL:
        return V5_PROVISIONAL[tid]
    try:
        import rooms_v4ind as RV
    except ModuleNotFoundError:
        return {}
    return RV.PROVISIONAL_DEF if tid in RV.V4_ROOMS else {}
