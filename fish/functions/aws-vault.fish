function aws-vault --description 'aws-vault with AWS_MFA_SERIAL defaulted for interactive use'
    # aws-vault >= v5 doesn't inherit mfa_serial from source_profile, and the
    # role profiles in aws/config deliberately omit it so `aws --profile X`
    # never prompts for MFA itself. Direct `aws-vault exec|login <role profile>`
    # therefore fails with "mfa serial not specified". There is no CLI flag for
    # it, only the AWS_MFA_SERIAL env var, so scope it to this one invocation.
    #
    # In the ByteNess fork (v7.11+), AWS_MFA_SERIAL only fills in profiles whose
    # mfa_serial is empty, and a single-role chain (capra-auth > role) assumes
    # the role directly from the IAM keys, with the OTP coming from the
    # mfa_process it inherits from capra-auth. So the serial is the only thing
    # missing on the role profile.
    #
    # Only this function sets it: the `credential_process` line in aws/config
    # is spawned by the AWS CLI/SDK (no fish involved) and capra-auth has its
    # own mfa_serial, so nothing outside interactive use is affected.
    if set -q AWS_MFA_SERIAL; and test -n "$AWS_MFA_SERIAL"
        command aws-vault $argv
    else
        env AWS_MFA_SERIAL=arn:aws:iam::259731000386:mfa/jstr aws-vault $argv
    end
end
