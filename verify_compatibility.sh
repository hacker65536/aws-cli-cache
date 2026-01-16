#!/usr/bin/env bash
# Final compatibility verification

echo "=== AWS CLI Cache - Shell Compatibility Verification ==="
echo ""

# Test 1: Bash syntax check
echo "Test 1: Bash syntax check"
if bash -n aws_cache.sh && bash -n lib/*.sh; then
    echo "✓ All files pass bash syntax check"
else
    echo "✗ Bash syntax check failed"
    exit 1
fi

# Test 2: Zsh syntax check
echo ""
echo "Test 2: Zsh syntax check"
if zsh -n aws_cache.sh && for f in lib/*.sh; do zsh -n "$f" || exit 1; done; then
    echo "✓ All files pass zsh syntax check"
else
    echo "✗ Zsh syntax check failed"
    exit 1
fi

# Test 3: Bash source test
echo ""
echo "Test 3: Bash source and function availability"
if bash -c 'source ./aws_cache.sh && type aws_cached >/dev/null 2>&1'; then
    echo "✓ Bash: aws_cached function available"
else
    echo "✗ Bash: Function not available"
    exit 1
fi

# Test 4: Zsh source test
echo ""
echo "Test 4: Zsh source and function availability"
if zsh -c 'source ./aws_cache.sh && type aws_cached >/dev/null 2>&1'; then
    echo "✓ Zsh: aws_cached function available"
else
    echo "✗ Zsh: Function not available"
    exit 1
fi

# Test 5: Unit tests
echo ""
echo "Test 5: Running unit tests"
if bash tests/unit/run_unit_tests.sh >/dev/null 2>&1; then
    echo "✓ All unit tests passed"
else
    echo "✗ Unit tests failed"
    exit 1
fi

echo ""
echo "========================================="
echo "✓ All compatibility tests passed!"
echo "========================================="
echo ""
echo "Supported shells:"
echo "  - bash 4.0+"
echo "  - zsh 5.0+"
echo ""
echo "Supported platforms:"
echo "  - macOS (BSD)"
echo "  - Linux (GNU)"
