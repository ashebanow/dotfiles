# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the
actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | *(no label)*         | Maintainer needs to evaluate this issue  |
| `needs-info`               | *(no label)*         | Waiting on reporter for more information |
| `ready-for-agent`          | `Ready For Agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | *(no label)*         | Requires human implementation            |
| `wontfix`                  | *(no label)*         | Will not be actioned                     |

When a skill mentions a role, use the string from the table. Where the string is *(no label)*,
express the role as described below — do **not** invent a label to fill the gap.

## Why four of the five roles have no label

Boxbow models triage state in Linear **workflow states**, not labels. The workspace labels are:

- **Category**: `Feature`, `Bug`, `Improvement` — pair exactly one with the state label
- **State**: `Ready For Agent`
- **Parking**: `Deferred`

The four roles without a label resolve like this:

| Role              | How it is expressed                                                            |
| ----------------- | ------------------------------------------------------------------------------ |
| `needs-triage`    | The issue is simply unlabeled — the skill's own "Unlabeled" bucket             |
| `needs-info`      | No label and no state change; post triage notes as a comment                   |
| `ready-for-human` | Expressed by the **absence** of `Ready For Agent`; post the brief as a comment |
| `wontfix`         | The `Won't Fix` canceled state, or `Canceled`                                  |

## Triage labels are orthogonal to workflow states

Linear tracks board state via statuses (`Todo`, `In Progress`, `Done`, …) and `/triage` applies
the role labels above. Both namespaces coexist on the same issue; don't conflate
`Ready For Agent` with the `Todo` status (triage role vs. workflow state).
