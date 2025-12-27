---
description: Formats, analyzes, tests, and pushes changes to the repository.
---

// turbo-all

1. Format the code to ensure style consistency
```bash
flutter format .
```

2. Run static analysis to catch potential issues
```bash
flutter analyze .
```

3. Execute the test suite
```bash
flutter test
```

4. Stage all modified files
```bash
git add .
```

5. Commit the changes
> agent should decide for a commit message
```bash
git commit
```

6. Push the committed changes to the remote repository
```bash
git push
```