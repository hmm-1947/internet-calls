"""Phone-number helpers with no Firebase dependency.

Kept separate from `firebase_phone` so modules such as the Pydantic schemas can
normalise a number without importing (and initialising) the Firebase SDK.
"""

import re


def normalize_indian_phone(phone: str) -> str:
    """Return the bare 10 digits of an Indian mobile number.

    Accepts the common ways a number is typed or returned by Firebase
    (`+91XXXXXXXXXX`, `0XXXXXXXXXX`, spaces or dashes) and raises ValueError
    when what is left is not a valid 10-digit mobile number.
    """
    digits = re.sub(r"\D", "", phone or "")
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    if len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) != 10 or digits[0] not in "6789":
        raise ValueError("Enter a valid 10-digit Indian phone number")
    return digits
