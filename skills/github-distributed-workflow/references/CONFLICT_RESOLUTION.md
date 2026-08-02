# Conflict Resolution

If you encounter a merge conflict, do NOT blindly accept "ours" or "theirs".

Analyze the semantic intent of both changes.

Propose and implement a resolution that preserves the intended functionality of both branches.

## Practical steps

1. Read both sides of every conflict marker (`<<<<<<<`, `=======`, `>>>>>>>`) in full — don't resolve a hunk from a diff summary alone.
2. Identify what each side was trying to accomplish (check the commit messages/PR context on both branches if unclear).
3. If the two changes are additive (e.g., both add different fields to the same function), merge them into a single version that includes both.
4. If the two changes are genuinely contradictory (e.g., both changed the same line to do different, incompatible things), do not guess — surface the conflict to the user with both intents explained and ask which should win, or propose a reconciliation and confirm before applying it.
5. After resolving, re-run the test suite before committing the merge — a conflict resolution that compiles is not the same as one that's correct.
6. Never resolve a conflict in a security-sensitive file (auth, permissions, CI/CD config) without calling out that you did so and why.
