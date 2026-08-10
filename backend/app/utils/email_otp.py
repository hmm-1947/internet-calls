import secrets
import smtplib
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage
from app.core.config import settings

logger = logging.getLogger("email_otp")

LOGO_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "logo.png")

_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="otp-email")

MAX_SEND_RETRIES = 3
RETRY_BACKOFF_SECONDS = 1.5


def generate_otp_code() -> str:
    return str(secrets.randbelow(900000) + 100000)


def _build_message(to_email: str, otp_code: str) -> MIMEMultipart:
    subject = "Your verification code"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;background-color:#0B0F1A;font-family:Arial,sans-serif;">
        <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0B0F1A;padding:40px 0;">
            <tr>
                <td align="center">
                    <table width="420" cellpadding="0" cellspacing="0" style="background-color:#15070A;border:2px solid #E53950;border-radius:16px;overflow:hidden;box-shadow:0 0 25px rgba(229,57,80,0.35);">
                        <tr>
                            <td align="center" style="background-color:#000000;padding:24px;border-bottom:2px solid #E53950;">
                                <img src="cid:logo_cid" width="90" height="90" style="border-radius:50%;border:3px solid #E53950;" alt="Logo"/>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:32px 28px 8px 28px;">
                                <p style="color:#FFFFFF;font-size:16px;margin:0 0 6px 0;">Verify your email</p>
                                <p style="color:#8A8F98;font-size:13px;margin:0;">Use the code below to complete your verification</p>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:24px 28px;">
                                <table cellpadding="0" cellspacing="0">
                                    <tr>
                                        <td style="background-color:#000000;border:2px solid #E53950;border-radius:10px;padding:16px 32px;">
                                            <span style="color:#E53950;font-size:32px;font-weight:bold;letter-spacing:8px;">{otp_code}</span>
                                        </td>
                                    </tr>
                                </table>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="padding:0 28px 28px 28px;">
                                <p style="color:#8A8F98;font-size:12px;margin:0;">This code expires in 10 minutes.</p>
                                <p style="color:#8A8F98;font-size:12px;margin:8px 0 0 0;">If you didn't request this, you can ignore this email.</p>
                            </td>
                        </tr>
                        <tr>
                            <td align="center" style="background-color:#000000;padding:14px;border-top:2px solid #E53950;">
                                <p style="color:#E53950;font-size:12px;margin:0;letter-spacing:1px;">LAILA NOW</p>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>
        </table>
    </body>
    </html>
    """

    msg = MIMEMultipart("related")
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from_email
    msg["To"] = to_email

    alt_part = MIMEMultipart("alternative")
    alt_part.attach(MIMEText(f"Your OTP code is {otp_code}. It expires in 10 minutes.", "plain"))
    alt_part.attach(MIMEText(html_body, "html"))
    msg.attach(alt_part)

    if os.path.exists(LOGO_PATH):
        with open(LOGO_PATH, "rb") as f:
            logo_img = MIMEImage(f.read())
            logo_img.add_header("Content-ID", "<logo_cid>")
            logo_img.add_header("Content-Disposition", "inline", filename="logo.png")
            msg.attach(logo_img)
    else:
        logger.warning(f"Logo file not found at {LOGO_PATH}")

    return msg


def _send_with_retry(to_email: str, otp_code: str, msg: MIMEMultipart) -> bool:
    last_error = None
    for attempt in range(1, MAX_SEND_RETRIES + 1):
        try:
            with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=10) as server:
                server.login(settings.smtp_user, settings.smtp_password)
                refused = server.sendmail(settings.smtp_from_email, [to_email], msg.as_string())
                if refused:
                    logger.info(f"sendmail refused recipients: {refused}")
                    return False
            logger.info(f"OTP email sent to {to_email}")
            return True
        except (smtplib.SMTPServerDisconnected, smtplib.SMTPConnectError, smtplib.SMTPHeloError, TimeoutError, OSError) as e:
            last_error = e
            logger.warning(f"Transient SMTP error sending to {to_email} (attempt {attempt}/{MAX_SEND_RETRIES}): {e}")
            if attempt < MAX_SEND_RETRIES:
                time.sleep(RETRY_BACKOFF_SECONDS * attempt)
        except Exception as e:
            logger.exception(f"Failed to send OTP email to {to_email}: {e}")
            return False
    logger.error(f"Giving up sending OTP email to {to_email} after {MAX_SEND_RETRIES} attempts: {last_error}")
    return False


def send_otp_email(to_email: str, otp_code: str):
    """Queue the OTP email on a background thread so the request isn't held
    open for a slow SMTP round trip. Returns the Future; existing callers
    that ignore it keep today's fire-and-forget behavior, but a caller that
    wants to know whether the email actually went out can now do
    `future.result(timeout=...)` to find out instead of the outcome being
    unreachable."""
    msg = _build_message(to_email, otp_code)
    return _executor.submit(_send_with_retry, to_email, otp_code, msg)

