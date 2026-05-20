-- Automatically provisions a player profile and default settings whenever a new user registers.
-- Runs as SECURITY DEFINER so it can write to public tables from the auth schema context.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  -- Create the player profile, pulling the nickname from the registration metadata
  INSERT INTO public.Players (id, nickname)
  VALUES (
    new.id,
    new.raw_user_meta_data ->> 'nickname'
  );

  -- Create a settings row with default values for the new user
  INSERT INTO public.Settings (user_id)
  VALUES (new.id);

  RETURN new;
END;
$$;

-- Fire the provisioning function after every new row in auth.users (i.e. every registration)
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();