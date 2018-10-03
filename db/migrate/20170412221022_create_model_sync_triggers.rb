class CreateModelSyncTriggers < ActiveRecord::Migration[5.0]
  def up
    execute <<-EOS
      CREATE OR REPLACE FUNCTION model_create_sync()
        RETURNS TRIGGER AS $$
      BEGIN
        PERFORM pg_notify('model_sync', concat('create ', TG_ARGV[0], ' ', NEW.id));
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION model_delete_sync()
        RETURNS TRIGGER AS $$
      BEGIN
        PERFORM pg_notify('model_sync', concat('delete ', TG_ARGV[0], ' ', OLD.id));
        RETURN OLD;
      END
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION model_update_sync()
        RETURNS TRIGGER AS $$
      BEGIN
        PERFORM pg_notify('model_sync', concat('update ', TG_ARGV[0], ' ', NEW.id));
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;

      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            CREATE TRIGGER ' || t || 's_create_sync
            AFTER INSERT ON ' || t || 's
            FOR EACH ROW
            EXECUTE PROCEDURE model_create_sync(' || quote_ident(t) || ');
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;

      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            CREATE TRIGGER ' || t || 's_delete_sync
            AFTER DELETE ON ' || t || 's
            FOR EACH ROW
            EXECUTE PROCEDURE model_delete_sync(' || quote_ident(t) || ');
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;

      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            CREATE TRIGGER ' || t || 's_update_sync
            AFTER UPDATE ON ' || t || 's
            FOR EACH ROW
            WHEN (OLD.updated_at IS DISTINCT FROM NEW.updated_at)
            EXECUTE PROCEDURE model_update_sync(' || quote_ident(t) || ');
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;
    EOS
  end

  def down
    execute <<-EOS
      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            DROP TRIGGER IF EXISTS ' || t || 's_create_sync ON ' || t || 's;
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;

      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            DROP TRIGGER IF EXISTS ' || t || 's_delete_sync ON ' || t || 's;
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;

      DO $$ BEGIN
        EXECUTE (
          SELECT string_agg('
            DROP TRIGGER IF EXISTS ' || t || 's_update_sync ON ' || t || 's;
          ', E'\n')
          FROM unnest('{attachment, campaign, goal, group, mailer, resource, scenario, template, victim}'::text[]) t
        );
      END $$ LANGUAGE plpgsql;

      DROP FUNCTION IF EXISTS model_create_sync();
      DROP FUNCTION IF EXISTS model_delete_sync();
      DROP FUNCTION IF EXISTS model_update_sync();
    EOS
  end
end
