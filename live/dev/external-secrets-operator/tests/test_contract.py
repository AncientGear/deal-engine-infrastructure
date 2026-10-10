"""Offline Terragrunt guards; no state, AWS or cluster access."""
import re
import unittest
from pathlib import Path

UNIT = Path(__file__).resolve().parents[1]


class OperatorLiveContract(unittest.TestCase):
    def setUp(self):
        self.live = (UNIT / "terragrunt.hcl").read_text()

    def test_published_source_is_pinned(self):
        expected = (
            "git@github.com:AncientGear/infrastructure-modules.git//aws/external-secrets-operator?ref=external-secrets-operator-v0.1.0"
        )
        self.assertRegex(
            self.live,
            rf'source\s*=\s*"{re.escape(expected)}"',
        )

    def test_eks_dependency_and_inputs(self):
        self.assertRegex(
            self.live,
            r'dependency\s+"eks"\s*\{\s*config_path\s*=\s*"\.\./eks"',
        )
        self.assertRegex(
            self.live,
            r"cluster_name\s*=\s*dependency\.eks\.outputs\.eks_name",
        )
        self.assertRegex(
            self.live,
            r"region\s*=\s*include\.env\.locals\.region",
        )
        self.assertRegex(
            self.live,
            r'mock_outputs_allowed_terraform_commands\s*=\s*\["validate"\]',
        )

    def test_generated_helm_connection(self):
        self.assertRegex(self.live, r'generate\s+"helm_provider"\s*\{')
        self.assertRegex(self.live, r'path\s*=\s*"helm-provider\.tf"')
        for source in ["aws_eks_cluster", "aws_eks_cluster_auth"]:
            self.assertRegex(
                self.live,
                rf'data\s+"{source}"\s+"eks"\s*\{{'
                rf"\s*name\s*=\s*var\.cluster_name",
            )
        for pattern in [
            r"host\s*=\s*data\.aws_eks_cluster\.eks\.endpoint",
            r"cluster_ca_certificate\s*=\s*base64decode\("
            r"data\.aws_eks_cluster\.eks\.certificate_authority\[0\]\.data\)",
            r"token\s*=\s*data\.aws_eks_cluster_auth\.eks\.token",
        ]:
            self.assertRegex(self.live, pattern)


if __name__ == "__main__":
    unittest.main()