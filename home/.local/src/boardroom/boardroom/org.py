"""The org chart: who has which role, chosen automatically or by hand.

A member is a table in company.toml:
  [[member]]
  id = "worker-1"
  role = "worker"
  model = "claude:sonnet"           # account:model
  subagent_model = "claude:haiku"   # optional; model for the subagents this member spawns
"""

from __future__ import annotations

from dataclasses import dataclass

from boardroom import catalog
from boardroom.catalog import TIER_RANK, ModelInfo

BUILTIN_ROLES = {
    "ceo": "Plans the work, does the hardest parts, hands out tasks and signs off on the result.",
    "debugger": "Checks the work: runs it, finds the root cause of failures and fixes them.",
    "worker": "Does the tasks the CEO hands out, spawning subagents for parallel parts.",
}

TEMPLATES = {
    "startup": "CEO + debugger + workers",
    "pair": "CEO + debugger",
    "solo": "just a CEO (who still spawns subagents)",
}


@dataclass(frozen=True)
class Candidate:
    account: str
    kind: str
    model: str
    info: ModelInfo

    @property
    def ref(self) -> str:
        return f"{self.account}:{self.model}"


class OrgError(Exception):
    pass


def candidates(accounts: dict, overrides: dict | None = None) -> list[Candidate]:
    out = []
    for name, acc in accounts.items():
        if acc.get("disabled"):
            continue
        for m in acc.get("models", []):
            out.append(Candidate(name, acc.get("kind", "?"), m, catalog.classify(m, overrides)))
    return out


def _best(cands, tiers=None, exclude_family=None, exclude_ref=None):
    pool = [
        c for c in cands
        if (tiers is None or c.info.tier in tiers)
        and (exclude_family is None or c.info.family != exclude_family)
        and c.ref != exclude_ref
    ]
    # better tier first, then higher score
    return min(pool, key=lambda c: (TIER_RANK[c.info.tier], -c.info.score), default=None)


def subagent_model_for(ref: str, cands: list[Candidate]) -> str | None:
    """The best 'fast' model on the same account, or None (= use the member's own model)."""
    account = ref.split(":", 1)[0]
    fast = [c for c in cands if c.account == account and c.info.tier == "fast"]
    if not fast:
        return None
    return max(fast, key=lambda c: c.info.score).ref


def auto_members(accounts: dict, workers: int = 4, template: str = "startup",
                 spread: bool = False, overrides: dict | None = None) -> list[dict]:
    cands = candidates(accounts, overrides)
    if not cands:
        raise OrgError("No models to hire from. Connect an account first: boardroom connect")
    if template not in TEMPLATES:
        raise OrgError(f"Unknown template {template!r}. Choose one of: {', '.join(TEMPLATES)}")

    ceo = _best(cands, tiers=("frontier",)) or _best(cands)
    members = [_member("ceo", "ceo", ceo.ref, cands)]

    if template in ("startup", "pair"):
        # A different maker's model sees the work with fresh eyes.
        dbg = (_best(cands, tiers=("frontier", "strong"), exclude_family=ceo.info.family)
               or _best(cands, exclude_ref=ceo.ref) or ceo)
        members.append(_member("debugger", "debugger", dbg.ref, cands))

    if template == "startup" and workers > 0:
        for i, c in enumerate(_worker_models(cands, workers, spread), 1):
            members.append(_member(f"worker-{i}", "worker", c.ref, cands))
    return members


def _worker_models(cands, n, spread):
    tiers = [("strong",), ("frontier",), ("fast",)]
    for t in tiers:
        pool = sorted((c for c in cands if c.info.tier in t), key=lambda c: -c.info.score)
        if pool:
            break
    if not spread:
        return [pool[0]] * n
    # The best model of each account, best accounts first, dealt out round-robin.
    per_account = {}
    for c in pool:
        per_account.setdefault(c.account, c)
    picks = list(per_account.values())
    return [picks[i % len(picks)] for i in range(n)]


def _member(id_, role, ref, cands):
    m = {"id": id_, "role": role, "model": ref}
    sub = subagent_model_for(ref, cands)
    if sub and sub != ref:
        m["subagent_model"] = sub
    return m


# --- editing by hand -----------------------------------------------------------------------

def check_ref(ref: str, accounts: dict) -> str:
    if ":" not in ref:
        # "sonnet" alone is fine if exactly one account has it
        hits = [f"{a}:{ref}" for a, acc in accounts.items() if ref in acc.get("models", [])]
        if len(hits) == 1:
            return hits[0]
        if not hits:
            raise OrgError(f"No connected account has a model called {ref!r}. See: boardroom models")
        raise OrgError(f"{ref!r} is on several accounts; say which: {', '.join(hits)}")
    account, model = ref.split(":", 1)
    if account not in accounts:
        raise OrgError(f"No account called {account!r}. See: boardroom accounts")
    if model not in accounts[account].get("models", []):
        # still allowed: the model list may just be out of date
        pass
    return ref


def next_id(members: list[dict], role: str) -> str:
    if role in ("ceo", "debugger") and not any(m["id"] == role for m in members):
        return role
    taken = {m["id"] for m in members}
    i = 1
    while f"{role}-{i}" in taken:
        i += 1
    return f"{role}-{i}"


def hire(company: dict, role: str, ref: str, accounts: dict, count: int = 1,
         id_: str | None = None) -> list[str]:
    roles = {**BUILTIN_ROLES, **company.get("roles", {})}
    if role not in roles:
        raise OrgError(f"Unknown role {role!r}. Roles: {', '.join(roles)} "
                       "(add your own under [roles.<name>] in company.toml)")
    if role == "ceo" and any(m["role"] == "ceo" for m in company["member"]):
        raise OrgError("There is already a CEO. Replace it with: boardroom org set ceo <account:model>")
    ref = check_ref(ref, accounts)
    cands = candidates(accounts, company.get("models"))
    added = []
    for _ in range(count):
        mid = id_ if (id_ and count == 1 and role != "ceo") else next_id(company["member"], role)
        if any(m["id"] == mid for m in company["member"]):
            raise OrgError(f"There is already a member called {mid!r}")
        company["member"].append(_member(mid, role, ref, cands))
        added.append(mid)
    return added


def fire(company: dict, member_id: str) -> None:
    m = find(company, member_id)
    if m["role"] == "ceo":
        raise OrgError("The company needs a CEO. Replace it with: boardroom org set ceo <account:model>")
    company["member"].remove(m)


def set_model(company: dict, who: str, ref: str, accounts: dict, subagents: bool = False) -> list[str]:
    """who = a member id, a role ("ceo"), or a plural role ("workers") for all of them."""
    ref = check_ref(ref, accounts)
    targets = [m for m in company["member"] if m["id"] == who]
    if not targets:
        role = who[:-1] if who.endswith("s") else who
        targets = [m for m in company["member"] if m["role"] == role]
    if not targets:
        if who == "ceo" and not subagents:
            company["member"].insert(0, {"id": "ceo", "role": "ceo", "model": ref})
            return ["ceo"]
        raise OrgError(f"No member or role called {who!r}")
    cands = candidates(accounts, company.get("models"))
    for m in targets:
        if subagents:
            m["subagent_model"] = ref
        else:
            m["model"] = ref
            sub = subagent_model_for(ref, cands)
            if sub and sub != ref:
                m["subagent_model"] = sub
            else:
                m.pop("subagent_model", None)
    return [m["id"] for m in targets]


def find(company: dict, member_id: str) -> dict:
    for m in company["member"]:
        if m["id"] == member_id:
            return m
    raise OrgError(f"No member called {member_id!r}")


def validate(company: dict, accounts: dict) -> list[str]:
    """Problems that stop a run, in plain words."""
    problems = []
    members = company.get("member", [])
    if not members:
        problems.append("The company has nobody in it yet. Run: boardroom setup (or boardroom org auto)")
    elif not any(m.get("role") == "ceo" for m in members):
        problems.append("The company has no CEO. Run: boardroom org set ceo <account:model>")
    else:
        ceos = [m["id"] for m in members if m.get("role") == "ceo"]
        if ceos != ["ceo"]:
            problems.append(f"There must be exactly one CEO, with id \"ceo\" (found: {', '.join(ceos)})")
    ids = [m.get("id") for m in members]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"Two members have the id {dup!r}")
    for m in members:
        for key in ("model", "subagent_model"):
            ref = m.get(key)
            if ref and ref.split(":", 1)[0] not in accounts:
                problems.append(f"{m['id']} uses {ref}, but there is no account called "
                                f"{ref.split(':', 1)[0]!r} any more")
    return problems
