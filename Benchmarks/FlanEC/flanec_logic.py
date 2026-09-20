"""Pure prompt and evaluation data for the throwaway FlanEC prototype."""

from dataclasses import dataclass


PROMPT_PREFIX = (
    "Generate the correct transcription for the following n-best list of ASR "
    "hypotheses:"
)


@dataclass(frozen=True)
class EvaluationCase:
    name: str
    hypotheses: tuple[str, ...]
    expected: str


def format_prompt(hypotheses: tuple[str, ...]) -> str:
    numbered = "".join(
        f"{index}. {hypothesis}\n"
        for index, hypothesis in enumerate(hypotheses, start=1)
    )
    return f"{PROMPT_PREFIX}\n\n{numbered}"


def repeated_one_best(text: str) -> tuple[str, ...]:
    """Simulate Textify's current one-best result in FlanEC's five-best shape."""
    return (text,) * 5


BUILT_IN_CASES = (
    EvaluationCase(
        name="published_widget_control",
        hypotheses=(
            "nebode also typically is symphons and an ankle surf leash",
            "neboda is also typically is symphons and an ankle surf leash",
            "nebode also typically is swim fins and an ankle surf leash",
            "neboda also typically is symphons and an ankle surf leash",
            "neboda is also typically is swim fins and an ankle surf leash",
        ),
        expected="neboda also typically is swim fins and an ankle surf leash",
    ),
    EvaluationCase(
        name="sota_one_best",
        hypotheses=repeated_one_best("this is a soda model"),
        expected="this is a SOTA model",
    ),
    EvaluationCase(
        name="sota_candidates",
        hypotheses=(
            "this is a soda model",
            "this is a sota model",
            "this is a sort of model",
            "this is the sota model",
            "this is a soda modal",
        ),
        expected="this is a SOTA model",
    ),
    EvaluationCase(
        name="soda_control",
        hypotheses=repeated_one_best("i drank a soda with lunch"),
        expected="i drank a soda with lunch",
    ),
    EvaluationCase(
        name="two_one_best",
        hypotheses=repeated_one_best("there are to models available"),
        expected="there are two models available",
    ),
    EvaluationCase(
        name="two_candidates",
        hypotheses=(
            "there are to models available",
            "there are two models available",
            "there are too models available",
            "there are two model available",
            "their are two models available",
        ),
        expected="there are two models available",
    ),
    EvaluationCase(
        name="filename_one_best",
        hypotheses=repeated_one_best("open fixes dot md"),
        expected="open fixes.md",
    ),
    EvaluationCase(
        name="filename_candidates",
        hypotheses=(
            "open fixes dot md",
            "open fixes dot m d",
            "open fixes.md",
            "open fixes md",
            "open fix is dot md",
        ),
        expected="open fixes.md",
    ),
    EvaluationCase(
        name="already_correct_sota",
        hypotheses=repeated_one_best("this is a SOTA model"),
        expected="this is a SOTA model",
    ),
)
