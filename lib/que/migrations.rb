module Que
  module Migrations
    CURRENT_VERSION = 2

    class << self
      def migrate!(options = {:version => CURRENT_VERSION})
        transaction do
          version = options[:version]

          if (current = db_version) == version
            return
          elsif current < version
            direction = 'up'
            steps = ((current + 1)..version).to_a
          elsif current > version
            direction = 'down'
            steps = ((version + 1)..current).to_a.reverse
          end

          steps.each do |step|
            Que.execute File.read("#{File.dirname(__FILE__)}/migrations/#{step}-#{direction}.sql")
          end

          set_db_version(version)
        end
      end

      def db_version
        result = Que.execute <<-SQL
          SELECT relname, description
          FROM pg_class
          LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
          WHERE relname = 'que_jobs'
        SQL

        if result.none?
          # No table in the database at all.
          0
        elsif (d = result.first[:description]).nil?
          # There's a table, it was just created before the migration system existed.
          1
        else
          d.to_i
        end
      end

      def set_db_version(version)
        i = version.to_i
        Que.execute "COMMENT ON TABLE que_jobs IS '#{i}'" unless i.zero?
      end

      def transaction
        Que.adapter.checkout do
          if in_transaction?
            yield
          else
            begin
              Que.execute "BEGIN"
              yield
            rescue => error
              raise
            ensure
              # Handle a raised error or a killed thread.
              if error || Thread.current.status == 'aborting'
                Que.execute "ROLLBACK"
              else
                Que.execute "COMMIT"
              end
            end
          end
        end
      end

      def in_transaction?
        # We don't know whether the connection we're using is already in a
        # transaction or not (it would be if running in an ActiveRecord or
        # Sequel migration). And unfortunately, Postgres doesn't seem to
        # offer a simple function to test whether we're already in a
        # transaction. So, minor hack - get the current transaction id
        # twice, and if it's the same each time, we're in a transaction.

        a, b = 2.times.map { Que.execute("SELECT txid_current()").first[:txid_current] }
        a == b
      end
    end
  end
end
