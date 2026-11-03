import secrets
import smtplib
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from email.utils import formataddr
from app.core.config import settings

logger = logging.getLogger("email_otp")

BRAND_NAME = "LailaNow"
DEFAULT_OTP_VALID_MINUTES = 5

LOGO_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "admin_logo.png")

_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="otp-email")

MAX_SEND_RETRIES = 3
RETRY_BACKOFF_SECONDS = 1.5


def generate_otp_code() -> str:
    return str(100000 + secrets.randbelow(900000))


PURPOSES = {
    "login": {
        "label": "authentication code",
        "heading": "Your authentication code",
        "intro": "Enter this code to finish signing in. Please don't share it with anyone.",
        "ignore": "If you didn't try to sign in, please reset your password as soon as possible.",
    },
    "reset": {
        "label": "password reset code",
        "heading": "Reset your password",
        "intro": "Enter this code to reset your password. Please don't share it with anyone.",
        "ignore": "If you didn't request a password reset, you can safely ignore this email. Your password won't change.",
    },
    "invite": {
        "label": "verification code",
        "heading": "Verify your email",
        "intro": "Enter this code to verify your email and finish your admin sign-up.",
        "ignore": "If you didn't expect this invitation, you can safely ignore this email.",
    },
}


def _build_message(to_email: str, otp_code: str, valid_minutes: int, purpose: str = "login") -> MIMEMultipart:
    info = PURPOSES.get(purpose, PURPOSES["login"])
    subject = f"Your {BRAND_NAME} {info['label']}: {otp_code}"
    logo_exists = os.path.exists(LOGO_PATH)
    minutes_label = f"{valid_minutes} minute{'s' if valid_minutes != 1 else ''}"
    digits = "".join(
        f'<td style="padding:0 4px;"><div style="width:44px;height:56px;line-height:56px;text-align:center;'
        f'background-color:#fff5f5;border:1px solid #f6c9cd;border-radius:10px;color:#c1121f;'
        f'font-size:28px;font-weight:700;font-family:\'Segoe UI\',Arial,sans-serif;">{d}</div></td>'
        for d in otp_code
    )

    logo_html = (
        f'<img src="cid:logo_cid" height="56" style="display:block;height:56px;width:auto;border:0;" alt="{BRAND_NAME}"/>'
        if logo_exists
        else f'<p style="margin:0;color:#e63946;font-size:20px;font-weight:700;letter-spacing:2px;text-transform:uppercase;">{BRAND_NAME}</p>'
    )

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;background-color:#f5f6f9;font-family:'Segoe UI',Arial,sans-serif;">
        <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Valid for {minutes_label}. Don\x27t share this code with anyone.</div>
        <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f6f9;padding:40px 12px;">
            <tr>
                <td align="center">
                    <table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background-color:#ffffff;border:1px solid #ecedf1;border-radius:16px;overflow:hidden;">
                        <tr>
                            <td style="background-color:#e63946;height:6px;font-size:0;line-height:0;">&nbsp;</td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:32px 32px 4px 32px;">
                                {logo_html}
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:20px 32px 0 32px;">
                                <h1 style="margin:0 0 8px 0;color:#1f2430;font-size:22px;font-weight:700;">{info["heading"]}</h1>
                                <p style="margin:0;color:#7c8493;font-size:14px;line-height:1.6;">{info["intro"]}</p>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:28px 32px 8px 32px;">
                                <table cellpadding="0" cellspacing="0"><tr>{digits}</tr></table>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:16px 32px 8px 32px;">
                                <p style="margin:0;color:#1f2430;font-size:13px;">This code is valid for <strong>{minutes_label}</strong>.</p>
                            </td>
                        </tr>
                        <tr>
                            <td style="padding:24px 32px 0 32px;">
                                <div style="border-top:1px solid #ecedf1;"></div>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:18px 32px 30px 32px;">
                                <p style="margin:0;color:#7c8493;font-size:12px;line-height:1.6;">{info["ignore"]}</p>
                            </td>
                        </tr>
                    </table>
                    <p style="margin:18px 0 0 0;color:#9aa2b1;font-size:11px;">&copy; {BRAND_NAME}</p>
                </td>
            </tr>
        </table>
    </body>
    </html>
    """

    msg = MIMEMultipart("related")
    alt = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = formataddr((BRAND_NAME, settings.smtp_from_email))
    msg["To"] = to_email
    alt.attach(MIMEText(
        f"Your {BRAND_NAME} {info['label']}: {otp_code}\n\nValid for {minutes_label}. "
        f"If you didn't request this, you can ignore this email.",
        "plain",
    ))
    alt.attach(MIMEText(html_body, "html"))
    msg.attach(alt)
    if logo_exists:
        with open(LOGO_PATH, "rb") as f:
            logo_img = MIMEImage(f.read())
        logo_img.add_header("Content-ID", "<logo_cid>")
        logo_img.add_header("Content-Disposition", "inline")
        msg.attach(logo_img)
    return msg


def _send_with_retry(to_email: str, otp_code: str, msg: MIMEMultipart):
    last_error = None
    for attempt in range(1, MAX_SEND_RETRIES + 1):
        try:
            with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=10) as server:
                server.login(settings.smtp_user, settings.smtp_password)
                refused = server.sendmail(settings.smtp_from_email, [to_email], msg.as_string())
                if refused:
                    logger.info(f"sendmail refused recipients: {refused}")
            logger.info(f"OTP email sent to {to_email}")
            return
        except (smtplib.SMTPServerDisconnected, smtplib.SMTPConnectError, smtplib.SMTPHeloError, TimeoutError, OSError) as e:
            last_error = e
            logger.warning(f"Transient SMTP error sending to {to_email} (attempt {attempt}/{MAX_SEND_RETRIES}): {e}")
            if attempt < MAX_SEND_RETRIES:
                time.sleep(RETRY_BACKOFF_SECONDS * attempt)
        except Exception as e:
            logger.exception(f"Failed to send OTP email to {to_email}: {e}")
            return
    logger.error(f"Giving up sending OTP email to {to_email} after {MAX_SEND_RETRIES} attempts: {last_error}")


def send_otp_email(to_email: str, otp_code: str, valid_minutes: int = DEFAULT_OTP_VALID_MINUTES, purpose: str = "login"):
    msg = _build_message(to_email, otp_code, valid_minutes, purpose)
    _executor.submit(_send_with_retry, to_email, otp_code, msg)
