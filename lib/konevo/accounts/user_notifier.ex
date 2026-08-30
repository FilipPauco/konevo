defmodule Konevo.Accounts.UserNotifier do
  @moduledoc false

  import Swoosh.Email

  alias Konevo.Accounts.User
  alias Konevo.Mailer

  @brand "#4f46e5"
  @ink "#172033"

  defp deliver(recipient, subject, content) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:konevo, :mailer_from))
      |> subject(subject)
      |> text_body(content.text)
      |> html_body(content.html)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your new email address",
      notification(%{
        eyebrow: "ACCOUNT SETTINGS",
        title: "Confirm your new email address",
        intro: "We received a request to update the email address for your Konevo account.",
        action: "Confirm email address",
        url: url,
        note:
          "This link is only for changing your email address. If you did not request it, you can safely ignore this email."
      })
    )
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(
      user.email,
      "Reset your password",
      notification(%{
        eyebrow: "ACCOUNT SECURITY",
        title: "Reset your password",
        intro: "A password reset was requested for your Konevo account.",
        action: "Reset password",
        url: url,
        note:
          "For your security, this link expires soon. If you did not request a password reset, no action is needed."
      })
    )
  end

  @doc """
  Delivers an invitation to finish setting up a tenant owner account.
  """
  def deliver_tenant_invitation(email, organization, url) do
    deliver(
      email,
      "Set up your Konevo workspace",
      notification(%{
        eyebrow: "WORKSPACE INVITATION",
        title: "Your workspace is ready",
        intro: "You have been invited to own the #{organization.name} workspace in Konevo.",
        action: "Set up workspace",
        url: url,
        note:
          "Finish setup within 3 days. Use your existing Konevo password if you already have an account; otherwise, you will create one."
      })
    )
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      "Your secure Konevo sign-in link",
      notification(%{
        eyebrow: "SECURE SIGN-IN",
        title: "Sign in to Konevo",
        intro:
          "Use this secure link to access your Konevo workspace without entering your password.",
        action: "Sign in securely",
        url: url,
        note:
          "This sign-in link is personal to you. If you did not request it, you can safely ignore this email."
      })
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your Konevo account",
      notification(%{
        eyebrow: "WELCOME TO KONEVO",
        title: "Confirm your email address",
        intro: "One quick step remains before you can start using your Konevo workspace.",
        action: "Confirm my account",
        url: url,
        note: "If you did not create a Konevo account, you can safely ignore this email."
      })
    )
  end

  defp notification(%{
         eyebrow: eyebrow,
         title: title,
         intro: intro,
         action: action,
         url: url,
         note: note
       }) do
    %{
      text: text_content(title, intro, action, url, note),
      html: html_content(eyebrow, title, intro, action, url, note)
    }
  end

  defp text_content(title, intro, action, url, note) do
    """
    KONEVO

    #{title}

    #{intro}

    #{action}:
    #{url}

    #{note}

    - The Konevo team
    """
  end

  defp html_content(eyebrow, title, intro, action, url, note) do
    assigns = %{
      action: escape(action),
      eyebrow: escape(eyebrow),
      intro: escape(intro),
      logo_url: escape(logo_url()),
      note: escape(note),
      title: escape(title),
      url: escape(url)
    }

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="x-apple-disable-message-reformatting">
      </head>
      <body style="margin:0; padding:0; background-color:#f4f6fb; color:#{@ink}; font-family:Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
        <div style="display:none; max-height:0; overflow:hidden; opacity:0; mso-hide:all;">#{assigns.title}</div>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f4f6fb;">
          <tr>
            <td align="center" style="padding:36px 16px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;">
                <tr>
                  <td style="padding:0 12px 18px;">
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                      <tr>
                        <td width="38" height="38" style="width:38px; height:38px; border-radius:11px; background-color:#{@brand}; text-align:center; vertical-align:middle;">
                          <img src="#{assigns.logo_url}" width="30" height="30" alt="Konevo" style="display:block; width:30px; height:30px; margin:4px; border:0; object-fit:contain;">
                        </td>
                        <td style="padding-left:10px; color:#{@ink}; font-size:20px; font-weight:750; letter-spacing:-0.4px;">Konevo</td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="overflow:hidden; border-radius:20px; background-color:#ffffff; box-shadow:0 12px 32px rgba(23, 32, 51, 0.08);">
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                      <tr>
                        <td style="height:5px; background:#{@brand}; font-size:0; line-height:0;">&nbsp;</td>
                      </tr>
                      <tr>
                        <td style="padding:42px 42px 18px;">
                          <div style="margin:0 0 18px; color:#{@brand}; font-size:11px; font-weight:800; letter-spacing:1.25px; line-height:16px;">#{assigns.eyebrow}</div>
                          <h1 style="margin:0; color:#{@ink}; font-size:30px; font-weight:750; letter-spacing:-0.8px; line-height:1.18;">#{assigns.title}</h1>
                          <p style="margin:20px 0 0; color:#536075; font-size:16px; line-height:25px;">#{assigns.intro}</p>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:10px 42px 28px;">
                          <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tr>
                              <td align="center" bgcolor="#{@brand}" style="border-radius:10px;">
                                <a href="#{assigns.url}" style="display:inline-block; padding:14px 22px; color:#ffffff; font-size:15px; font-weight:700; line-height:20px; text-decoration:none;">#{assigns.action} &rarr;</a>
                              </td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:0 42px 38px;">
                          <div style="border-left:3px solid #c7d2fe; border-radius:2px; background-color:#f8faff; padding:14px 16px; color:#66748a; font-size:13px; line-height:20px;">#{assigns.note}</div>
                          <p style="margin:24px 0 0; color:#7b8798; font-size:12px; line-height:19px;">Button not working? Copy and paste this link into your browser:<br><a href="#{assigns.url}" style="color:#{@brand}; text-decoration:underline; word-break:break-all;">#{assigns.url}</a></p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding:22px 12px 0; color:#8b96a8; font-size:12px; line-height:18px;">&copy; #{Date.utc_today().year} Konevo &middot; Built for focused customer relationships</td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp logo_url, do: KonevoWeb.Endpoint.url() <> "/images/logo-navbar-v2.png"

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
