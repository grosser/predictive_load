module PredictiveLoad::ActiveRecordCollectionObservation

  def self.included(base)
    ActiveRecord::Relation.class_attribute :collection_observer
    if ActiveRecord::VERSION::MAJOR >= 5
      ActiveRecord::Relation.prepend Rails5RelationObservation
    else
      ActiveRecord::Relation.prepend Rails4RelationObservation
    end
    ActiveRecord::Base.include CollectionMember
    ActiveRecord::Base.extend UnscopedTracker
    ActiveRecord::Associations::Association.include AssociationNotification
    ActiveRecord::Associations::CollectionAssociation.include CollectionAssociationNotification
  end

  module Rails5RelationObservation
    # this essentially intercepts the enumerable methods that would result in n+1s since most of
    # those are delegated to :records in Rails 5+ in the ActiveRecord::Relation::Delegation module
    def records
      record_array = super
      if record_array.size > 1 && collection_observer
        collection_observer.observe(record_array.dup)
      end
      record_array
    end
  end

  module Rails4RelationObservation
    # this essentially intercepts the enumerable methods that would result in n+1s since most of
    # those are delegated to :to_a in Rails 5+ in the ActiveRecord::Relation::Delegation module
    def to_a
      record_array = super
      if record_array.size > 1 && collection_observer
        collection_observer.observe(record_array.dup)
      end
      record_array
    end
  end

  module CollectionMember

    attr_accessor :collection_observer

  end

  # disable eager loading since includes + unscoped is broken on rails 4
  module UnscopedTracker
    if ActiveRecord::VERSION::MAJOR >= 4
      def unscoped
        if block_given?
          begin
            predictive_load_disabled << self
            super
          ensure
            predictive_load_disabled.pop
          end
        else
          super
        end
      end
    end

    def predictive_load_disabled
      Thread.current[:predictive_load_disabled] ||= []
    end
  end

  module AssociationNotification

    def self.included(base)
      base.send(:alias_method, :load_target_without_notification, :load_target)
      base.send(:alias_method, :load_target, :load_target_with_notification)
    end

    def load_target_with_notification
      notify_collection_observer if find_target?

      load_target_without_notification
    end

    protected

    def notify_collection_observer
      if @owner.collection_observer
        @owner.collection_observer.loading_association(@owner, self)
      end
    end

  end

  module CollectionAssociationNotification

    def self.included(base)
      base.send(:alias_method, :load_target_without_notification, :load_target)
      base.send(:alias_method, :load_target, :load_target_with_notification)
    end

    def load_target_with_notification
      notify_collection_observer if find_target?

      load_target_without_notification
    end

  end

end
