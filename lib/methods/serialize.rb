module EasyRoles
  class Serialize

    def initialize(base, column_name, options)
      base.serialize column_name.to_sym, Array

      ActiveSupport::Deprecation.silence do
        base.before_validation(:make_default_roles, on: :create)
      end

      base.send :define_method, :has_role? do |role|
        self[column_name.to_sym].include?(role)
      end

      base.send :define_method, :add_role do |role|
        clear_roles if self[column_name.to_sym].blank?

        has_role?(role) ? false : self[column_name.to_sym] << role
      end

      base.send :define_method, :add_role! do |role|
        return false if !base::ROLES_MARKER.empty? && role.include?(base::ROLES_MARKER)
        add_role(role)
        self.save!
      end

      base.send :define_method, :remove_role do |role|
        self[column_name.to_sym].delete(role)
      end

      base.send :define_method, :remove_role! do |role|
        remove_role(role)
        self.save!
      end

      base.send :define_method, :clear_roles do
        self[column_name.to_sym] = []
      end

      base.send :define_method, :make_default_roles do
        clear_roles if self[column_name.to_sym].blank?
      end

      base.send :private, :make_default_roles


      # Scopes (Ugly, no cross-table query support, potentially unsafe. Fix?)
      # ----------------------------------------------------------------------------------------------------
      # For security, wrapping markers must be included in the LIKE search, otherwise a user with
      # role 'administrator' would erroneously be included in `User.with_scope('admin')`. 
      #
      # Rails uses YAML for serialization, so the markers are newlines. Unfortunately, sqlite can't match
      # newlines reliably, and it doesn't natively support REGEXP. Therefore, hooks are currently being used
      # to wrap roles in '!' markers when talking to the database. This is hacky, but unavoidable. 
      # The implication is that, for security, it must be actively enforced that role names cannot include
      # the '!' character.
      #
      # An alternative would be to use JSON instead of YAML to serialize the data, but I've wrestled
      # countless SerializationTypeMismatch errors trying to accomplish this, in vain.
      # 
      # Adding a dependancy to something like Squeel would allow for cleaner syntax in the `where()`, with the
      # added bonus of supporting complex cross-table queries. The real problem, of course, is even trying to 
      # query serialized data. I'm unsure how well this would work in different ruby versions or implementations,
      # which may handle object dumping differently.

      base.class_eval do
        const_set :ROLES_MARKER, '!'

        define_method :add_role_markers do
          self[column_name.to_sym].map! { |r| [base::ROLES_MARKER,r,base::ROLES_MARKER].join }
        end
      
        define_method :strip_role_markers do
          self[column_name.to_sym].map! { |r| r.gsub(base::ROLES_MARKER,'') }
        end

        private :add_role_markers, :strip_role_markers
        before_save :add_role_markers
        after_save :strip_role_markers
        after_rollback :strip_role_markers
        after_find :strip_role_markers

        scope :with_role, proc { |r|
          query = "#{self.table_name}.#{column_name} LIKE " + ['"%',base::ROLES_MARKER,r,base::ROLES_MARKER,'%"'].join
          where(query)
        }
      end

    end
  end
end
